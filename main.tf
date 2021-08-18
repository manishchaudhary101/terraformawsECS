#TERRAFORM PROVIDER BLOCK
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.54.0"
    }
  }
}

#AWS PROVIDER BLOCK
provider "aws" {
  region = "ap-south-1"
}

#CREATING ECR REPO
resource "aws_ecr_repository" "foo" {
  name                 = "nodeapprepo"
  image_tag_mutability = "MUTABLE"

}


#CREATING ECS CLUSTER
resource "aws_ecs_cluster" "firstcluster" {
  name = "nodecluster"
}

#CREATING TASK DEFINITION 
resource "aws_ecs_task_definition" "NodeappTaskDefinition" {
      family      = "NodeappTaskDefinition" 
  container_definitions    = <<DEFINITION
  [
    {
      "name": "NodeappTaskDefinition",
      "image": "nodeapprepo",      
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5001,
          "hostPort": 5001
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # USING FARGATE
  network_mode             = "awsvpc"    # USING AWS VPC
  memory                   = 512         # MEMORY OUR CONTAINER REQUIRES
  cpu                      = 256         # CPU OUR CONTAINER REQUIRES
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}


#CREATING REQUIRED IAM ROLE AND STS ASSUME ROLE
resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}


data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


#PROVINDING REFERENCE TO OUR DEFAULT VPC AND SUBNETS
resource "aws_default_vpc" "default_vpc" {
}
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "ap-south-1a"
}
resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "ap-south-1b"
}
resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "ap-south-1c"
}
resource "aws_ecs_service" "my_first_service" {
  name            = "my-first-service"                             # Naming our first service
  cluster         = "${aws_ecs_cluster.my_cluster.id}"             # Referencing our created Cluster
  task_definition = "${aws_ecs_task_definition.my_first_task.arn}" # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers to 3

  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Referencing our target group
    container_name   = "${aws_ecs_task_definition.my_first_task.family}"
    container_port   = 3000 # Specifying the container port
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true                                                # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Setting the security group
  }
}


resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}


#CREATING APPLICATION LOAD BALANCER
resource "aws_alb" "application_load_balancer" {
  name               = "Nodeapp-LB" 
  load_balancer_type = "application"
  subnets = [               #REFERENCE TO OUR AWS DEFAULT SUBNETS
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  #REFERENCING THE SECURITY GROUP
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

#CREATING SECURITY GROUP & SETTING UP ROUTES FOR APPLICATION LOAD BALANCER
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80 #TRAFFIC ALLOWED FROM PORT
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #ALLOWING TRAFFIC FROM IPS
  }

  egress {
    from_port   = 0 
    to_port     = 0 
    protocol    = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
}
}
#TARGET GROUP FOR ALB AND HEALTH CHECK PATH
resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" 
  health_check {
  healthy_threshold = "2"
  unhealthy_threshold = "6"
  interval = "30"
  matcher = "200,301,302"
  path = "/"
  protocol = "HTTP"
  timeout = "5"
}
}
#ALB LISTENER PORT
resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" 
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" 
}
}