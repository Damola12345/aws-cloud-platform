resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" 
  force_delete = true
  
  image_scanning_configuration {
    scan_on_push = true # basic vulnerability scanning - satisfies the "security check" requirement too
  }

  encryption_configuration {
    encryption_type = "KMS" # encrypted at rest with an AWS-managed KMS key
  }

  tags = var.tags
}

# Keep the repository tidy and cheap: expire untagged (dangling) images
# quickly, and cap the number of tagged images we keep around.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
