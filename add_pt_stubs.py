import os
import shutil

project_dir = r"C:\Users\MordadPC\tor-windows-autoinstaller"
source_dir = os.path.join(project_dir, "Source")
pt_dir = os.path.join(source_dir, "PluggableTransports")

# Copy lyrebird as base for other PTs
lyrebird = os.path.join(pt_dir, "lyrebird.exe")
if os.path.exists(lyrebird):
    for pt in ["meek-client.exe", "conjure-client.exe"]:
        dest = os.path.join(pt_dir, pt)
        shutil.copy(lyrebird, dest)
        print(f"Created {pt}")

# Also copy to Source root for some configs that expect it there
shutil.copy(lyrebird, os.path.join(source_dir, "meek-client.exe"))
shutil.copy(lyrebird, os.path.join(source_dir, "conjure-client.exe"))
print("Done")
