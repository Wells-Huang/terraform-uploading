# ==========================================
# Lambda 函數 - TODO API
# ==========================================

# 打包 Lambda 函數程式碼
data "archive_file" "lambda_todo" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/todo"
  output_path = "${path.module}/lambda-todo.zip"
}

resource "aws_lambda_function" "todo_api" {
  filename      = data.archive_file.lambda_todo.output_path
  function_name = "${var.project_name}-todo-api"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 10
  memory_size   = 256

  source_code_hash = data.archive_file.lambda_todo.output_base64sha256

  environment {
    variables = {
      TODO_BUCKET_NAME = aws_s3_bucket.todo_data.bucket
      TODO_OBJECT_KEY  = "todos.json"
    }
  }

  tags = {
    Name = "TODO API Lambda Function"
  }
}

# Lambda 日誌群組
resource "aws_cloudwatch_log_group" "lambda_todo" {
  name              = "/aws/lambda/${aws_lambda_function.todo_api.function_name}"
  retention_in_days = 7

  tags = {
    Name = "TODO Lambda Logs"
  }
}

# ==========================================
# Lambda 函數 - Generate Upload URL
# ==========================================

data "archive_file" "lambda_generate_url" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/generate_upload_url"
  output_path = "${path.module}/lambda-generate-url.zip"
}

resource "aws_lambda_function" "generate_upload_url" {
  filename      = data.archive_file.lambda_generate_url.output_path
  function_name = "${var.project_name}-generate-upload-url"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 10
  memory_size   = 256

  source_code_hash = data.archive_file.lambda_generate_url.output_base64sha256

  environment {
    variables = {
      TODO_BUCKET_NAME = aws_s3_bucket.todo_data.bucket
    }
  }

  tags = {
    Name = "Generate Upload URL Lambda"
  }
}

resource "aws_cloudwatch_log_group" "lambda_generate_url" {
  name              = "/aws/lambda/${aws_lambda_function.generate_upload_url.function_name}"
  retention_in_days = 7

  tags = {
    Name = "Generate Upload URL Lambda Logs"
  }
}

# ==========================================
# Lambda 函數 - Crop Image
# ==========================================

# 確保提供給 Lambda 的 sharp 是 linux-x64 架構編譯的
resource "null_resource" "build_sharp_layer" {
  triggers = {
    package_json = filemd5("${path.module}/../lambda/crop_image/package.json")
    index_js     = filemd5("${path.module}/../lambda/crop_image/index.js")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/../lambda/crop_image && npm install --os=linux --cpu=x64 sharp"
  }
}

data "archive_file" "lambda_crop_image" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/crop_image"
  output_path = "${path.module}/lambda-crop-image.zip"
  
  depends_on = [null_resource.build_sharp_layer]
}

resource "aws_lambda_function" "crop_image" {
  filename      = data.archive_file.lambda_crop_image.output_path
  function_name = "${var.project_name}-crop-image"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30  # 圖片處理可能耗時長一點，設定30秒
  memory_size   = 512 # 圖片處理需要較多記憶體

  source_code_hash = data.archive_file.lambda_crop_image.output_base64sha256

  environment {
    variables = {
      TODO_BUCKET_NAME = aws_s3_bucket.todo_data.bucket
    }
  }

  tags = {
    Name = "Crop Image Lambda"
  }
}

resource "aws_cloudwatch_log_group" "lambda_crop_image" {
  name              = "/aws/lambda/${aws_lambda_function.crop_image.function_name}"
  retention_in_days = 7

  tags = {
    Name = "Crop Image Lambda Logs"
  }
}
