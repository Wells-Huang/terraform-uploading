# ==========================================
# CloudFront Distribution
# ==========================================

resource "aws_cloudfront_origin_access_identity" "todo_data_oai" {
  comment = "OAI to access processed images in todo-data bucket"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} CDN Distribution"
  default_root_object = ""  # API Gateway 會處理根路徑
  price_class         = "PriceClass_200"  # 亞洲、歐洲、北美

  # Origin - S3 Todo Data (for processed images)
  origin {
    domain_name = aws_s3_bucket.todo_data.bucket_regional_domain_name
    origin_id   = "todo-data-s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.todo_data_oai.cloudfront_access_identity_path
    }
  }

  # Origin - API Gateway
  origin {
    domain_name = replace(aws_api_gateway_stage.prod.invoke_url, "/^https?://([^/]*).*/", "$1")
    origin_id   = "api-gateway"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default Cache Behavior - 靜態內容
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api-gateway"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Cache Behavior - /processed/* (圖片快取)
  ordered_cache_behavior {
    path_pattern     = "/processed/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "todo-data-s3"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  # Cache Behavior - /api/* (不快取)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api-gateway"

    forwarded_values {
      query_string = true
      headers      = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = false
  }

  # 地區限制 - 台灣 + 日本
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = var.allowed_countries
    }
  }

  # SSL/TLS 憑證
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "Main CloudFront Distribution"
  }
}
