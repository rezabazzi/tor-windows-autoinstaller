import os
import struct

project_dir = r"C:\Users\MordadPC\tor-windows-autoinstaller"
source_dir = os.path.join(project_dir, "Source")
output_dir = os.path.join(project_dir, "Output")

os.makedirs(source_dir, exist_ok=True)
os.makedirs(output_dir, exist_ok=True)

# Create minimal Windows PE executable stub
def create_stub_exe(path, name):
    """Create a minimal valid Windows PE executable"""
    # DOS Header
    dos_header = bytearray(64)
    dos_header[0:2] = b'MZ'
    dos_header[60:64] = struct.pack('<I', 64)  # PE offset
    
    # PE Signature
    pe_sig = b'PE\x00\x00'
    
    # COFF Header (minimal)
    coff_header = bytearray(20)
    coff_header[0:2] = struct.pack('<H', 0x14C)  # Machine: i386
    coff_header[2:4] = struct.pack('<H', 1)       # Number of sections
    coff_header[4:8] = struct.pack('<I', 0)       # Time stamp
    coff_header[8:12] = struct.pack('<I', 0)      # Symbol table offset
    coff_header[12:16] = struct.pack('<I', 0)     # Number of symbols
    coff_header[16:18] = struct.pack('<H', 224)   # Optional header size
    coff_header[18:20] = struct.pack('<H', 0x102) # Characteristics
    
    # Optional Header (minimal)
    opt_header = bytearray(224)
    opt_header[0:2] = struct.pack('<H', 0x10B)    # PE32
    opt_header[16:20] = struct.pack('<I', 0x1000) # Entry point
    opt_header[20:24] = struct.pack('<I', 0x1000) # Base of code
    opt_header[24:28] = struct.pack('<I', 0x2000) # Base of data
    opt_header[28:32] = struct.pack('<I', 0x400000) # Image base
    opt_header[32:36] = struct.pack('<I', 0x1000) # Section alignment
    opt_header[36:40] = struct.pack('<I', 0x200)  # File alignment
    opt_header[56:60] = struct.pack('<I', 0x4000) # Size of image
    opt_header[60:64] = struct.pack('<I', 0x200)  # Size of headers
    
    # Section header
    section_header = bytearray(40)
    section_header[0:8] = b'.text\x00\x00\x00'
    section_header[8:12] = struct.pack('<I', 0x100)   # Virtual size
    section_header[12:16] = struct.pack('<I', 0x1000) # Virtual address
    section_header[16:20] = struct.pack('<I', 0x100)   # Size of raw data
    section_header[20:24] = struct.pack('<I', 0x200)   # Pointer to raw data
    section_header[36:40] = struct.pack('<I', 0x60000020)  # Characteristics
    
    # Pad to 512 bytes total
    data = bytes(dos_header) + pe_sig + bytes(coff_header) + bytes(opt_header) + bytes(section_header)
    data += b'\x00' * (512 - len(data))
    
    with open(path, 'wb') as f:
        f.write(data)
    
    print(f"Created stub: {path} ({len(data)} bytes)")

# Create stubs for required files
stub_files = ['tor.exe', 'nssm.exe']
for stub in stub_files:
    create_stub_exe(os.path.join(source_dir, stub), stub)

# Create DLL stubs
dll_stubs = ['libssl-3.dll', 'libcrypto-3.dll', 'libevent-2-1-7.dll', 'zlib1.dll']
for dll in dll_stubs:
    create_stub_exe(os.path.join(source_dir, dll), dll)

# Create PluggableTransports stubs
pt_dir = os.path.join(source_dir, "PluggableTransports")
os.makedirs(pt_dir, exist_ok=True)
create_stub_exe(os.path.join(pt_dir, "lyrebird.exe"), "lyrebird.exe")
create_stub_exe(os.path.join(pt_dir, "snowflake-client.exe"), "snowflake-client.exe")

print("All stubs created!")
