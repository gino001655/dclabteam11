import sys
import os

# Import the montgomery multiplication methods from golden.rsa
# Adjust path to find it
sys.path.append(os.path.join(os.path.dirname(__file__), 'golden'))
from rsa import power_mont

def rsa_sign(msg_bytes, d, n):
    """
    Sign a 32-byte message using RSA private key (d, n).
    msg_bytes: bytes object (length 32)
    Returns: signed bytes object (length 32)
    """
    assert len(msg_bytes) <= 32
    
    # Convert bytes to large integer
    msg_int = 0
    for byte in msg_bytes:
        msg_int = (msg_int << 8) | byte
        
    # Sign using montgomery exponentiation: S = M^d mod n
    sig_int = power_mont(msg_int, d, n)
    
    # Convert back to 32 bytes
    sig_bytes = bytearray()
    for _ in range(32):
        sig_bytes.append(sig_int & 0xFF)
        sig_int >>= 8
    
    sig_bytes.reverse()
    return bytes(sig_bytes)

def rsa_verify(sig_bytes, e, n):
    """
    Verify a 32-byte signature using RSA public key (e, n).
    sig_bytes: bytes object (length 32)
    Returns: recovered message bytes object (length 32)
    """
    assert len(sig_bytes) == 32
    
    # Convert bytes to large int
    sig_int = 0
    for b in sig_bytes:
        sig_int = (sig_int << 8) | b
        
    # Verify: M' = S^e mod n
    rec_int = power_mont(sig_int, e, n)
    
    # Convert back to 32 bytes
    rec_bytes = bytearray()
    for _ in range(32):
        rec_bytes.append(rec_int & 0xFF)
        rec_int >>= 8
        
    rec_bytes.reverse()
    return bytes(rec_bytes)
