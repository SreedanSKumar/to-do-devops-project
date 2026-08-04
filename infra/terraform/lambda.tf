# ---------------------------------------------------------------------------
# S3 bucket that Lambda watches, and the Lambda itself.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "ops_data" {
  bucket = "${var.project}-events-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "ops_data" {
  bucket                  = aws_s3_bucket.ops_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_func.py"
  output_path = "${path.module}/lambda/lambda_func.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project}_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Basic CloudWatch Logs permissions - without this, the function runs but you
# can't see why it failed.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_read" {
  name = "${var.project}-lambda-s3-read"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.ops_data.arn}/*"
    }]
  })
}

resource "aws_lambda_function" "process_event" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "${var.project}-process-event"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_func.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.process_event.function_name}"
  retention_in_days = 14
}

# This is the piece the original config was missing: without an explicit
# permission, S3 is not allowed to invoke the function, and the bucket
# notification below silently never fires.
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_event.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ops_data.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.ops_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_event.arn
    events               = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
