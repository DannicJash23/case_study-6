provider "aws" {
  region  = "ap-south-1"
  profile = "kanth_testuser"
}

resource "random_id" "policy_id" {
  byte_length = 4
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "secure_bucket" {
  bucket = "secure-access-bucket-${random_id.bucket_id.hex}"

  lifecycle {
    prevent_destroy = false
  }
}

# Output the bucket name 
output "bucket_name" { 
  value = aws_s3_bucket.secure_bucket.bucket 
  }

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.secure_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle_config" {
  bucket = aws_s3_bucket.secure_bucket.id

  rule {
    id     = "expire-objects-rule"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "secure_bucket_policy" {
  bucket = aws_s3_bucket.secure_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAccountAccess"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.secure_bucket.id}"
      },
      {
        Sid       = "AllowObjectActions"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.secure_bucket.id}/*"
      },
      {
        Sid       = "AllowCloudTrail"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.secure_bucket.id}/AWSLogs/*"
      },
      { 
        Sid = "AWSCloudTrailAclCheck" 
        Effect = "Allow" 
        Principal = { Service = "cloudtrail.amazonaws.com" } 
        Action = "s3:GetBucketAcl" 
        Resource = "arn:aws:s3:::${aws_s3_bucket.secure_bucket.id}" 
      },
      { 
        Sid = "AWSCloudTrailWrite" 
        Effect = "Allow" 
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = "s3:PutObject" 
        Resource = "arn:aws:s3:::${aws_s3_bucket.secure_bucket.id}/AWSLogs/*" 
        Condition = { 
          StringEquals = { 
            "s3:x-amz-acl" = "bucket-owner-full-control" 
          } 
        }
      },
    ]
  })
}



resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_iam_role" "s3_access_role" {
  name = "ec2-s3-access-role-${random_id.policy_id.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3-access-policy-${random_id.policy_id.hex}"
  description = "Policy for S3 Access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:ListBucket",
          "s3:HeadBucket",
          "s3:GetBucketPolicy",
          "s3express:PutBucketPolicy"
        ]
        Resource = "arn:aws:s3:::secure-access-bucket-${random_id.bucket_id.hex}"
      },
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::secure-access-bucket-${random_id.bucket_id.hex}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach_policy" {
  role       = aws_iam_role.s3_access_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Security Group to allow SSH, HTTP, and HTTPS traffic
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2-security-group"
  description = "Allow SSH, HTTP, and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

  # Allow SSH (port 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS (port 443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2-Security-Group"
  }
}

resource "aws_instance" "ec2_instance" {
  ami           = "ami-0dee22c13ea7a9a67"  # Replace with a valid AMI ID
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.subnet.id
  key_name = "casestudy4"
  security_groups = [aws_security_group.ec2_security_group.id]
  
  iam_instance_profile = aws_iam_instance_profile.s3_access_profile.name
  
  tags = {
    Name = "S3-Access-Instance"
  }

provisioner "file" {
  source = "C:/Users/YelisettyK/Downloads/case-study6/read_s3.sh"
  destination = "/home/ubuntu/read_s3.sh"

connection {
  type = "ssh"
  host = self.public_ip
  user = "ubuntu"
  private_key = file("C:/Users/YelisettyK/Downloads/case-study6/casestudy4.pem")
  }
 }
}



resource "aws_iam_instance_profile" "s3_access_profile" {
  name = "s3-access-instance-profile-${random_id.policy_id.hex}"
  role = aws_iam_role.s3_access_role.name
}

# Create CloudTrail
resource "aws_cloudtrail" "cloudtrail" {
  name                          = "ec2-and-s3-trail"
  s3_bucket_name                = aws_s3_bucket.secure_bucket.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  depends_on = [ 
    aws_s3_bucket_policy.secure_bucket_policy
   ]
}

# Create VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-south-1.s3"

  tags = {
    Name = "terraform-vpc-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_association" {
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
  route_table_id = aws_route_table.route_table.id
  
}
