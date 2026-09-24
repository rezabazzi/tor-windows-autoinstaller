import subprocess
import os

iscc_path = os.path.expanduser(r"~\AppData\Local\Programs\Inno Setup 6\ISCC.exe")
project_dir = r"C:\Users\MordadPC\tor-windows-autoinstaller"

print(f"ISCC path: {iscc_path}")
print(f"Exists: {os.path.exists(iscc_path)}")

if os.path.exists(iscc_path):
    print(f"Building...")
    result = subprocess.run([iscc_path, "Tor-Installer.iss"], 
                          cwd=project_dir, 
                          capture_output=True, text=True)
    print("STDOUT:", result.stdout)
    print("STDERR:", result.stderr)
    print("Return code:", result.returncode)
    
    # List output files
    output_dir = os.path.join(project_dir, "Output")
    if os.path.exists(output_dir):
        for f in os.listdir(output_dir):
            if f.endswith('.exe'):
                print(f"\nOutput: {os.path.join(output_dir, f)}")
                print(f"Size: {os.path.getsize(os.path.join(output_dir, f))} bytes")
else:
    print("ISCC not found")
    # Try to find it
    for root, dirs, files in os.walk(os.path.expanduser(r"~\AppData\Local\Programs")):
        for f in files:
            if f == "ISCC.exe":
                print(f"Found at: {os.path.join(root, f)}")
