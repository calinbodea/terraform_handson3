#!/bin/bash
yum update -y
yum install httpd -y
echo "<h1>this is my test environment $(hostname -f)</h1>" >> /var/www/html/index.html
systemctl start httpd
systemctl enable httpd