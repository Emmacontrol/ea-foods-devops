# One repository per service, shared by staging and production:
# an image is built once and the SAME digest is promoted from staging to production.

resource "aws_ecr_repository" "service" {
  for_each = var.services

  name                 = "ea-foods/${each.key}"
  image_tag_mutability = "IMMUTABLE" # a tag (git SHA) can never point at different code

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged layers after 7 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last ${var.ecr_keep_images} images (rollback window)"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.ecr_keep_images }
        action       = { type = "expire" }
      },
    ]
  })
}
