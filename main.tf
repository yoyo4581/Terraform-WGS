provider "aws" {
    region = "us-east-1"
    shared_credentials_files = ["/Users/Yahya/.aws/credentials"]
}

#------------------VPC and HPC configuration------------------
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

#----------------Account Sensitive Information----------------
variable "aws_account_number" {
    description = "The AWS account number"
    type = string
    sensitive = true
}

# -------------------------------
# SUBNETS: Private for Spot + FSx + Fargate
# -------------------------------
resource "aws_subnet" "spot_subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/25"
  availability_zone = "us-east-1a"
  tags = { Name = "spot-subnet-1" }
}

resource "aws_subnet" "spot_subnet_2" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/25"
  availability_zone = "us-east-1b"
  tags = { Name = "spot-subnet-2" }
}

resource "aws_subnet" "fsx_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/25"
  availability_zone = "us-east-1a" # FSx must be in a single AZ
  tags = { Name = "fsx-subnet" }
}

resource "aws_subnet" "fargate_subnet" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.0.0/25"
    tags = {
        "Name" = "FargateSubnet"
    }
    tags_all = {
        "Name" = "FargateSubnet"
    }
}

# -------------------------------
# SECURITY GROUPS
# -------------------------------
# Security group for FSx (allows Spot instances to connect)
resource "aws_security_group" "fsx_sg" {
  vpc_id = aws_vpc.main_vpc.id
  name = "fsx-security-group"
  description = "Security group for FSx for Lustre"

  tags = {
    Name = "fsx-security-group"
  }
}

#---------------------------------------
# Allow Inbound and Outbound NGS TRAFFIC FROM SPOT INSTANCES to FSx
#----------------------------------------
resource "aws_vpc_security_group_ingress_rule" "fsx_allow_nfs_spot_1_ipv4" {
  security_group_id = aws_security_group.fsx_sg.id
  cidr_ipv4         = "10.0.1.0/25"  # Spot subnet 1
  from_port         = 988
  to_port           = 988
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "fsx_allow_nfs_spot_2_ipv4" {
  security_group_id = aws_security_group.fsx_sg.id
  cidr_ipv4         = "10.0.2.0/25"  # Spot subnet 2
  from_port         = 988
  to_port           = 988
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "fsx_allow_all_outbound_spot_1_ipv4" {
  security_group_id = aws_security_group.fsx_sg.id
  cidr_ipv4         = "10.0.1.0/25"  # Spot subnet 1
  ip_protocol       = "-1"  # Allow all outbound traffic
}
resource "aws_vpc_security_group_egress_rule" "fsx_allow_all_outbound_spot_2_ipv4" {
  security_group_id = aws_security_group.fsx_sg.id
  cidr_ipv4         = "10.0.2.0/25"  # Spot subnet 2
  ip_protocol       = "-1"  # Allow all outbound traffic
}

#------------------------------------------
# Allow Outgoing Spot connections to FSx
#------------------------------------------

resource "aws_security_group" "spot_sg" {
    name = "spot-instance-sg"
    description = "Security group for spot instances running snakemake"
    vpc_id = aws_vpc.main_vpc.id
}

# Allow outbound traffic from Spot instances to FSx
resource "aws_vpc_security_group_egress_rule" "spot_allow_fsx_ipv4" {
    security_group_id = aws_security_group.spot_sg.id
    cidr_ipv4 = "10.0.3.0/25" # FSx subnet
    from_port = 988
    to_port = 988
    ip_protocol = "tcp"
}
# Allow outbound access to S3 (via VPC endpoint or internet)
resource "aws_vpc_security_group_egress_rule" "spot_allow_s3_ipv4" {
    security_group_id = aws_security_group.spot_sg.id
    cidr_ipv4 = "0.0.0.0/0" # Open for S3 access
    ip_protocol = "-1" # Allow all traffic
}



#terraform import aws_s3_bucket.wgs-genomics-input wgs-genomics-yoyo458
resource "aws_s3_bucket" "wgs-genomics-input" {
    bucket = "wgs-genomics-yoyo458"
}

variable "create_fsx" {
  type    = bool
  default = true
}
# fsx_volume id: fs-045f8c8ce4f06b95b
resource "aws_fsx_lustre_file_system" "fsx_volume" {
    count = var.create_fsx ? 1 : 0

    import_path = "s3://wgs-genomics-yoyo458/temp/"
    storage_capacity = 1200
    subnet_ids = [aws_subnet.fsx_subnet.id]
}


resource "aws_s3_bucket" "snakemake-folder" {
    bucket = "wgs-snakemake-files-yoyo458"
}

# Upload the Snakemake file
resource "aws_s3_object" "snakemake_file" {
  bucket = aws_s3_bucket.snakemake-folder.bucket
  key    = "Snakefile"
  source = "./snakemake-files/Snakefile"
  acl    = "private"
}

resource "aws_s3_object" "snakemake-additional" {
  for_each = fileset("./snakemake-files/snakemake_additional_files", "*.smk")

  bucket = aws_s3_bucket.snakemake-folder.bucket
  key    = "snakemake_additional_files/${each.value}"
  source = "./snakemake-files/snakemake_additional_files/${each.value}"
  # etag makes the file update when it changes; see https://stackoverflow.com/questions/56107258/terraform-upload-file-to-s3-on-every-apply
  etag   = filemd5("./snakemake-files/snakemake_additional_files/${each.value}")
}





resource "aws_ecs_cluster" "fargate-cluster" {
    name = "snakemake-fargate-cluster"
}

resource "aws_ecs_task_definition" "snakemake-task" {
    family = "snakemake-fargate-task"
    execution_role_arn = "arn:aws:iam::${var.aws_account_number}:role/ecsTaskExecutionRole"
    network_mode = "awsvpc"
    cpu = "512"
    memory = "1024"
    requires_compatibilities = ["FARGATE"]
    container_definitions = jsonencode([
        {
            "name": "snakemake-runner",
            "image": "${var.aws_account_number}.dkr.ecr.us-east-1.amazonaws.com/snakemake:latest",
            "cpu": 512,
            "memory": 1024,
            "portMappings": [],
            "essential": true,
            "command": [
                "sleep",
                "infinity"
            ],
            "environment": [
                {
                    "name": "TIBANNA_DEFAULT_STEP_FUNCTION_NAME",
                    "value": "tibanna_unicorn_my-unicorn-wgs"
                }
            ],
            "mountPoints": [],
            "volumesFrom": [],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/snakemake-logs",
                    "awslogs-region": "us-west-2",
                    "awslogs-stream-prefix": "snakemake"
                }
            },
            "systemControls": []
        }
    ])
}

data "archive_file" "trigger-snakemake-lambda" {
    type = "zip"
    source_file = "./lambda_functions/TriggerEventSnakemake/lambda_function.py"
    output_path = "./lambda_functions/TriggerEventSnakemake/lambda_function.zip"
}

resource "aws_lambda_function" "trigger-snakemake" {
    description = "Lambda function to trigger snakemake task"

    function_name = "TriggerEventSnakemake"
    role = "arn:aws:iam::${var.aws_account_number}:role/WGS-Trigger-LambdaRole"
    handler = "lambda_function.lambda_handler"
    runtime = "python3.10"
    filename = data.archive_file.trigger-snakemake-lambda.output_path
    source_code_hash = data.archive_file.trigger-snakemake-lambda.output_base64sha256
    tags = {
        "lambda-console:blueprint" = "s3-get-object-python"
    }
}

resource "aws_lambda_permission" "allow_bucket" {
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.trigger-snakemake.id
    source_account = "${var.aws_account_number}"
    principal = "s3.amazonaws.com"
    source_arn = aws_s3_bucket.snakemake-folder.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.snakemake-folder.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger-snakemake.arn
    events              = ["s3:ObjectCreated:Put"]
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}


data "archive_file" "check-task-awsem-lambda" {
    type = "zip"
    source_dir = "./lambda_functions/check_task_awsem_my-unicorn-wgs/check-task-repo/"
    output_path = "./lambda_functions/check_task_awsem_my-unicorn-wgs/lambda_function.zip"
}

resource "aws_lambda_function" "check_task_unicorn" {
    description = "check status of AWSEM run by interegating appropriate files on S3 "

    function_name = "check_task_awsem_my-unicorn-wgs"
    role = "arn:aws:iam::${var.aws_account_number}:role/tibanna_my-unicorn-wgs_check_task_awsem"
    handler = "service.handler"
    runtime = "python3.11"
    filename = data.archive_file.check-task-awsem-lambda.output_path
    source_code_hash = data.archive_file.check-task-awsem-lambda.output_base64sha256
    memory_size = 256
    timeout = 300
    environment {
        variables = {
            "SECURITY_GROUPS" = aws_security_group.spot_sg.id
            "SUBNETS" = "${aws_subnet.spot_subnet_1.id},${aws_subnet.spot_subnet_2.id}"
            "TIBANNA_DEFAULT_STEP_FUNCTION_NAME" = "tibanna_unicorn_my-unicorn-wgs"
            "TIBANNA_VERSION" = "5.5.0"
        }
    }
    vpc_config {
        ipv6_allowed_for_dual_stack = false
        security_group_ids = [aws_security_group.spot_sg.id]
        subnet_ids = [aws_subnet.spot_subnet_1.id, aws_subnet.spot_subnet_2.id]
    }
}


data "archive_file" "run-task-awsem-lambda" {
    type = "zip"
    source_dir = "./lambda_functions/run_task_awsem_my-unicorn-wgs/run-task-repo/"
    output_path = "./lambda_functions/run_task_awsem_my-unicorn-wgs/lambda_function.zip"
}

resource "aws_lambda_function" "run_task_unicorn" {
    description = "launch an ec2 instance"

    function_name = "run_task_awsem_my-unicorn-wgs"
    role = "arn:aws:iam::${var.aws_account_number}:role/tibanna_my-unicorn-wgs_run_task_awsem"
    handler = "service.handler"
    runtime = "python3.11"
    filename = data.archive_file.run-task-awsem-lambda.output_path
    source_code_hash = data.archive_file.run-task-awsem-lambda.output_base64sha256
    memory_size = 256
    timeout = 300
    environment {
        variables = {
            "SECURITY_GROUPS" = aws_security_group.spot_sg.id
            "SUBNETS" = "${aws_subnet.spot_subnet_1.id},${aws_subnet.spot_subnet_2.id}"
            "AWS_S3_ROLE_NAME" = "tibanna_my-unicorn-wgs_for_ec2"
            "TIBANNA_REPO_BRANCH" = "master"
            "TIBANNA_REPO_NAME" =  "4dn-dcic/tibanna"
            "TIBANNA_VERSION" = "5.5.0"
        }
    }
    vpc_config {
        ipv6_allowed_for_dual_stack = false
        security_group_ids = [aws_security_group.spot_sg.id]
        subnet_ids = [aws_subnet.spot_subnet_1.id, aws_subnet.spot_subnet_2.id]
    }
}



