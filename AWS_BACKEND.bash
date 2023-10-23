#!/bin/bash

# Install Python and Flask
sudo apt update -y
sudo apt install python3 python3-pip -y
sudo apt install -y python3-flask 

# Create a Python script for your Flask app
cat <<EOL > /home/ubuntu/app.py
from flask import Flask, jsonify
import sqlite3
from sqlite3 import Error

app = Flask(__name__)

# Function to create the SQLite database and table
def create_database():
    try:
        connection = sqlite3.connect('/home/ubuntu/my_database.sqlite')
        cursor = connection.cursor()
        
        # Define the table schema
        create_table_sql = """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            username TEXT NOT NULL,
            email TEXT,
            created_at DATETIME
        );
        """
        
        # Create the table
        cursor.execute(create_table_sql)
        
        # Insert sample data
        insert_data_sql = """
        INSERT INTO users (username, email, created_at) VALUES
        ('user1', 'user1@example.com', '2023-10-20T08:00:00'),
        ('user2', 'user2@example.com', '2023-10-20T09:00:00'),
        ('user3', 'user3@example.com', '2023-10-20T10:00:00');
        """
        cursor.execute(insert_data_sql)
        
        # Commit the changes and close the connection
        connection.commit()
        connection.close()
        
        print("Database created and sample data inserted successfully.")
    except Error as e:
        print(f"Error: {e}")
        
# Define a route to retrieve data from the database
@app.route('/api/users', methods=['GET'])
def get_users():
    try:
        connection = sqlite3.connect('/home/ubuntu/my_database.sqlite')
        cursor = connection.cursor()
        
        # Retrieve data from the users table
        cursor.execute("SELECT * FROM users")
        data = cursor.fetchall()
        
        connection.close()
        return jsonify(data)
    except Error as e:
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    # Create the database and table if they don't exist
    create_database()
    
    # Start the Flask app
    app.run(host='0.0.0.0', port=80)
EOL

sudo python3 home/ubuntu/app.py 
