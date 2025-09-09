from flask import Flask, render_template, request, jsonify, flash
import paramiko
import subprocess
import threading
import time
import os
from datetime import datetime

app = Flask(__name__)
app.secret_key = 'your-secret-key-change-this'

class HardwareCollector:
    def __init__(self):
        self.script_path = './scripts/collect_hardware.sh'
    
    def connect_ipmi(self, host, username, password):
        """Connect to IPMI and get basic info"""
        try:
            # Using ipmitool command - you might want to use pyghmi for better integration
            cmd = f"ipmitool -I lanplus -H {host} -U {username} -P {password} chassis status"
            result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                return {"status": "success", "data": result.stdout}
            else:
                return {"status": "error", "message": result.stderr}
        except subprocess.TimeoutExpired:
            return {"status": "error", "message": "IPMI connection timed out"}
        except Exception as e:
            return {"status": "error", "message": str(e)}
    
    def ssh_execute_script(self, host, username, password, port=22):
        """SSH into device and execute the hardware collection script"""
        try:
            # Create SSH client
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Connect
            ssh.connect(hostname=host, port=port, username=username, password=password, timeout=30)
            
            # Read the script content
            with open(self.script_path, 'r') as f:
                script_content = f.read()
            
            # Create a unique temporary script file name
            script_name = f"/tmp/hardware_collect_{int(time.time())}_{os.getpid()}.sh"
            
            # Upload script content
            stdin, stdout, stderr = ssh.exec_command(f'cat > {script_name}')
            stdin.write(script_content)
            stdin.close()
            
            # Wait for upload to complete
            stdout.channel.recv_exit_status()
            
            # Make it executable
            stdin, stdout, stderr = ssh.exec_command(f'chmod +x {script_name}')
            stdout.channel.recv_exit_status()  # Wait for completion
            
            # Execute the script
            stdin, stdout, stderr = ssh.exec_command(f'sudo {script_name}', timeout=120)
            
            # Get output
            output = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            exit_status = stdout.channel.recv_exit_status()
            
            # Clean up the temporary file
            stdin_cleanup, stdout_cleanup, stderr_cleanup = ssh.exec_command(f'sudo rm -f {script_name}')
            stdout_cleanup.channel.recv_exit_status()  # Wait for cleanup
            
            ssh.close()
            
            if exit_status != 0 and error and 'sudo' not in error.lower():
                return {"status": "error", "message": error}
            else:
                return {"status": "success", "data": output}
                
        except paramiko.AuthenticationException:
            return {"status": "error", "message": "SSH Authentication failed"}
        except paramiko.SSHException as e:
            return {"status": "error", "message": f"SSH Error: {str(e)}"}
        except Exception as e:
            return {"status": "error", "message": str(e)}

collector = HardwareCollector()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/collect', methods=['POST'])
def collect_hardware():
    try:
        data = request.get_json()
        
        # Get form data
        ipmi_host = data.get('ipmi_host', '').strip()
        ipmi_user = data.get('ipmi_user', '').strip()
        ipmi_pass = data.get('ipmi_pass', '').strip()
        ssh_host = data.get('ssh_host', '').strip()
        ssh_user = data.get('ssh_user', '').strip()
        ssh_pass = data.get('ssh_pass', '').strip()
        ssh_port = int(data.get('ssh_port', 22))
        
        results = {
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'ipmi': {},
            'hardware': {}
        }
        
        # Test IPMI connection if provided
        if ipmi_host and ipmi_user and ipmi_pass:
            ipmi_result = collector.connect_ipmi(ipmi_host, ipmi_user, ipmi_pass)
            results['ipmi'] = ipmi_result
        
        # Execute hardware collection via SSH
        if ssh_host and ssh_user and ssh_pass:
            ssh_result = collector.ssh_execute_script(ssh_host, ssh_user, ssh_pass, ssh_port)
            results['hardware'] = ssh_result
        else:
            results['hardware'] = {"status": "error", "message": "SSH credentials required"}
        
        return jsonify(results)
        
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == '__main__':
    # Ensure directories exist
    os.makedirs('scripts', exist_ok=True)
    os.makedirs('templates', exist_ok=True)
    os.makedirs('static', exist_ok=True)
    
    app.run(debug=True, host='0.0.0.0', port=5000)