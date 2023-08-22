#!/bin/bash
yum update -y
yum install -y docker
systemctl enable docker
systemctl restart docker
docker run -d -p 3306:3306 -e MYSQL_DATABASE=wordpressdb -e MYSQL_ROOT_PASSWORD=password mysql:5.7