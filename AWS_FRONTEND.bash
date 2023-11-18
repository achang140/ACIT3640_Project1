#!/bin/bash

# Update package list and install NGINX
sudo apt update -y
sudo apt install nginx -y

# Start NGINX and enable it to start on boot
sudo systemctl start nginx
sudo systemctl enable nginx

# Retrieve EC2 instance information
region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | awk -F'"' '/region/ {print $4}')
availability_zone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
subnet_id=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/)/subnet-id)
instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Function to generate the HTML content
generate_html() {
  cat <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>Concierge View</title>
    <style>
        table {
            width: 100%;
            border-collapse: collapse;
        }
        table, th, td {
            border: 1px solid black;
        }
        th, td {
            padding: 8px;
            text-align: left;
        }
    </style>
</head>
<body>
    <h1>Instance Info</h1>
    <ul>
        <li><strong>Region Name:</strong> $region</li>
        <li><strong>Availability Zone:</strong> $availability_zone</li>
        <li><strong>Subnet ID:</strong> $subnet_id</li>
        <li><strong>Instance ID:</strong> $instance_id</li>
    </ul>
    <h2>Concierge View</h2>
    <button id="fetch-data-button">Fetch Data</button>
    <table id="user-table-body">
        <thead>
            <tr>
                <th>Column 1</th>
                <th>Column 2</th>
                <th>Column 3</th>
                <th>Column 4</th>
            </tr>
        </thead>
        <tbody></tbody>
    </table>
    <script> 
        const button = document.querySelector('#fetch-data-button');
        const tbody = document.querySelector('#user-table-body tbody');
        button.addEventListener('click', () => {
            fetch('http://FrontASGTest-1-805204142.us-east-1.elb.amazonaws.com/users')
                .then(response => response.json())
                .then(data => {
                    tbody.innerHTML = ''; // Clear existing table rows
                    data.forEach(user => {
                        const row = document.createElement('tr');
                        user.forEach(cellData => {
                            const cell = document.createElement('td');
                            cell.textContent = cellData;
                            row.appendChild(cell);
                        });
                        tbody.appendChild(row);
                    });
                })
                .catch(error => {
                    console.error('Error:', error);
                });
        });
    </script>
</body>
</html>
HTML
}

# Generate the HTML content and save it to /var/www/html/index.html
generate_html > /var/www/html/index.html

# Reload NGINX configuration
sudo systemctl reload nginx

nginx_conf=$(cat <<EOF
server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;
        server_name _;
        location / {
                try_files \$uri \$uri/ =404;
        }
        location /users {
            proxy_pass http://BackNLB-01d42b99e02378dc.elb.us-east-1.amazonaws.com/api/users;
            # Set CORS headers
            add_header 'Access-Control-Allow-Origin' 'http://acit3640.acyc.link';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
            if (\$request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' 'http://acit3640.acyc.link';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' 0;
                return 204;
            }
        }
}
EOF
)

# Backup default nginx config file and write the new config and HTML files
sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup
sudo echo "$nginx_conf" > /etc/nginx/sites-available/default
sudo systemctl reload nginx
