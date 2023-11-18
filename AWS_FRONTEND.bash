#!/bin/bash

# Update package list and install NGINX
sudo apt update -y
sudo apt install nginx mysql-client awscli -y


# MySQL database credentials
HOST="mysql-rds.cxwdtgsgm2fs.us-east-1.rds.amazonaws.com" # RDS MySQL Endpoint
USER="admin"
PASSWORD="mysqldbfacts"
DATABASE="Facts"

# mysql -h mysql-rds.cxwdtgsgm2fs.us-east-1.rds.amazonaws.com -P 3306 -u admin -p 

mysql -h $HOST -P 3306 -u $USER -p$PASSWORD << EOF
CREATE DATABASE IF NOT EXISTS $DATABASE;
USE $DATABASE;

CREATE TABLE IF NOT EXISTS facts (
    fact_id INT AUTO_INCREMENT PRIMARY KEY,
    fact_content VARCHAR(255) NOT NULL
) ENGINE=INNODB; 

INSERT INTO facts (fact_content) 
VALUES 
    ("While not common, orcas will sometimes hunt moose"),
    ("Air hand dryers are actually much more unsanitary than paper towels"),
    ("A day on Venus lasts longer than a year on Venus"),
    ("Loading icons are called throbbers"),
    ("Cashews grow out of apples"),
    ("Spicy food is appealing because your brain thinks it's in pain so it releases dopamine and other endorphins"),
    ("The 9th largest pyramid in the world is a Bass Pro Shop"),
    ("Caffeine works by blocking adenosine receptors"),
    ("The area in between the eyes is called the glabella"),
    ("Sleep deprivation greatly increases your risk for early Alzheimer's"),
    ("Opossums don't actually 'play dead', they go unconscious due to an uncontrollable reaction from extreme stress"),
    ("Cuckoos are birds which will lay their eggs in other birds nests, tricking them into feeding and raising their young alright here's more facts"),
    ("Sloths metabolisms are so slow that they sometimes starve to death on a full stomach"),
    ("Whales sleep vertically for 15-30 minute periods"),
    ("You should close toilet lids before flushing because they shoot aerosolized particles into the air"),
    ("Cats are crepuscular, meaning they are most active at dusk and dawn"),
    ("Apple was the first company to be worth 1 trillion"),
    ("Contrary to what you see in TV, you should not use an AED on someone with no pulse. You're just shocking a dead person."),
    ("The majority of the earths oxygen comes from oceanic plankton"),
    ("Artificial rain can be created through cloud seeding, a process where small particles of silver iodide are added to clouds"),
    ("Human femurs have stronger tensile strength than steel and concrete");
EOF

query_result=$(mysql -h $HOST -P 3306 -u $USER -p$PASSWORD --skip-column-names -e "SELECT fact_content FROM $DATABASE.facts;")

echo -n '[' > /var/www/html/data.json  # Start JSON array
echo "$query_result" | awk '{print "{\"fact_content\":\"" $0 "\"},"}' | sed '$s/,$//' >> /var/www/html/data.json
echo ']' >> /var/www/html/data.json  # End JSON array


# Start NGINX and enable it to start on boot
sudo systemctl start nginx
sudo systemctl enable nginx

# https://aws.amazon.com/blogs/security/defense-in-depth-open-firewalls-reverse-proxies-ssrf-vulnerabilities-ec2-instance-metadata-service/
# IMDSv2 - Every request is now protected by session authentication 

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | awk -F'"' '/region/ {print $4}')
AVAILABILITY_ZONE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
SUBNET_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -n 1)/subnet-id)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

# Generate the HTML content
cat > /var/www/html/index.html << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Random Facts Generator</title>
    <style>
        body {
            background-color: pink;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }

        ul {
            position: absolute;
            top: 0;
            left: 0;
            margin: 10px;
            padding: 0;
            list-style: none;
        }

        button {
            padding: 10px;
            font-size: 16px;
            cursor: pointer;
            margin-top: 10px;
        }

        div#content-container {
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <ul>
        <li><strong>Region Name:</strong> $REGION</li>
        <li><strong>Availability Zone:</strong> $AVAILABILITY_ZONE</li>
        <li><strong>Subnet ID:</strong> $SUBNET_ID</li>
        <li><strong>Instance ID:</strong> $INSTANCE_ID</li>
    </ul>
    <button id="fetch-data-button">Generate Facts</button>
    <div id="content-container"></div>
    <script>
        const button = document.querySelector('#fetch-data-button');
        const contentContainer = document.querySelector('#content-container');

        button.addEventListener('click', () => {
            fetch('http://ALB-2143078415.us-east-1.elb.amazonaws.com/data.json') // Application Load Balancer DNS 
                .then(response => response.json())
                .then(data => {
                    console.log('Data:', data);

                    const randomIndex = Math.floor(Math.random() * data.length);
                    console.log('Random Index:', randomIndex);

                    const randomFact = data[randomIndex].fact_content;
                    console.log('Random Fact:', randomFact);

                    // Create a new p element
                    const newParagraph = document.createElement('p');
                    
                    // Set its text content to the random fact
                    newParagraph.textContent = randomFact;

                    // Clear existing content
                    contentContainer.innerHTML = '';
                    
                    // Append the new p element to the content container
                    contentContainer.appendChild(newParagraph);
                })
                .catch(error => {
                    console.error('Error:', error);
                });
        });
    </script>
</body>
</html>
HTML

# Update Nginx configuration
nginx_conf=$(cat <<EOF
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
            try_files \$uri \$uri/ =404;

            resolver            8.8.8.8; # Use your DNS resolver
            set                 \$db_endpoint $HOST; // RDS MySQL Endpoint
            set                 \$db_port 3306;
            proxy_pass          http://\$db_endpoint:\$db_port;
        }
    }
EOF
)

# Backup default nginx config file and write the new config and HTML files
sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup
echo "$nginx_conf" | sudo tee /etc/nginx/sites-available/default
sudo systemctl reload nginx
