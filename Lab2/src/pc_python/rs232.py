#!/usr/bin/env python
from serial import Serial, EIGHTBITS, PARITY_NONE, STOPBITS_ONE
import sys
import os
import time

assert len(sys.argv) >= 2, "Usage: python rs232.py <COM_PORT>"
port = sys.argv[1]

s = Serial(
    port=port,
    baudrate=115200,
    bytesize=EIGHTBITS,
    parity=PARITY_NONE,
    stopbits=STOPBITS_ONE,
    xonxoff=False,
    rtscts=False,
    timeout=1
)

# Open basic decryption files
fp_key = open('key.bin', 'rb')
fp_enc = open('enc.bin', 'rb')
fp_dec = open('dec.bin', 'wb')
assert fp_key and fp_enc and fp_dec

key = fp_key.read(64)
enc = fp_enc.read()
assert len(enc) % 32 == 0

# 0. Query FPGA mode
print("Querying FPGA mode...")
s.write(b'\xAA')
mode_byte = s.read(1)
if len(mode_byte) == 0:
    print("Error: FPGA did not respond to query. Is it programmed and reset?")
    sys.exit(1)

mode = int.from_bytes(mode_byte, byteorder='little')
if mode == 0:
    print("FPGA is in Mode: 0 (Normal)")
elif mode == 1:
    print("FPGA is in Mode: 1 (Certificate - Ready for Registration)")
elif mode == 2:
    print("FPGA is in Mode: 1 (Certificate - Public Key Already Enrolled)")

# Tell FPGA we are about to start a NEW session
s.write(b'\xBB')

if mode >= 1:
    import certificate
    
    # Check if keys exist
    public_key_path = 'pc_key/keys/public.bin'
    private_key_path = 'pc_key/keys/private.bin'
    
    if not os.path.exists(public_key_path) or not os.path.exists(private_key_path):
        print("Missing pc_key/keys/public.bin or private.bin! Please generate them.")
        sys.exit(1)
        
    fp_pub = open(public_key_path, 'rb')
    pub_key = fp_pub.read(64)
    fp_pub.close()
    
    fp_priv = open(private_key_path, 'rb')
    priv_key = fp_priv.read(64)
    fp_priv.close()
    
    if mode == 1:
        # Send public key to FPGA for verification setup (64 Bytes)
        print("Registering Public Key on FPGA...")
        s.write(pub_key)
    else:
        print("Using existing Public Key on FPGA.")
    
    # Extract private key parameters (d_pc, n_pc)
    n_pc_bytes = priv_key[0:32]
    d_pc_bytes = priv_key[32:64]
    
    n_pc = 0
    d_pc = 0
    for b in n_pc_bytes: n_pc = (n_pc << 8) | b
    for b in d_pc_bytes: d_pc = (d_pc << 8) | b

    print("Beginning Continuous Decryption Loop with Signatures...")
    for i in range(0, len(enc), 32):
        if i != 0:
            # Tell FPGA we are continuing to next chunk
            s.write(b'\xCC')
            
        chunk = enc[i:i+32]
        
        # Generator signature for this chunk
        sig_bytes = certificate.rsa_sign(chunk, d_pc, n_pc)
        
        # Send decryption key
        s.write(key)
        # Send ciphertext
        s.write(chunk)
        # Send signature
        s.write(sig_bytes)
        
        # Read Verification result
        dec = s.read(31)
        fp_dec.write(dec)
        
else:
    print("Beginning Continuous Normal Decryption Loop...")
    for i in range(0, len(enc), 32):
        if i != 0:
            # Tell FPGA we are continuing to next chunk
            s.write(b'\xCC')
            
        s.write(key)
        s.write(enc[i:i+32])
        dec = s.read(31)
        fp_dec.write(dec)

fp_key.close()
fp_enc.close()
fp_dec.close()
print("Process Completed.")
