import os
import random

def is_prime(n, k=5):
    if n < 2 or n % 2 == 0:
        return n == 2
    s, d = 0, n - 1
    while d % 2 == 0:
        s, d = s + 1, d // 2
    for _ in range(k):
        a = random.randrange(2, n - 1)
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(s - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True

def get_prime(bits):
    while True:
        p = random.getrandbits(bits)
        p |= (1 << (bits - 1)) | 1
        if is_prime(p):
            return p

def generate_mock_keys(directory, seed, golden_n):
    random.seed(seed)
    print(f"Generating valid RSA keypair for {directory}...")
    while True:
        p = get_prime(128)
        q = get_prime(128)
        n = p * q
        # Ensure N is strictly 256 bits, and strictly larger than the decryption modulus (golden_n)
        # to guarantee that S = M^d mod n does not cause M > n overflow.
        if n.bit_length() == 256 and n > golden_n:
            break
            
    phi = (p - 1) * (q - 1)
    e = 65537
    # e must be coprime to phi, generally 65537 is, but just to be safe:
    while True:
        try:
            d = pow(e, -1, phi)
            break
        except ValueError:
            e += 2
    
    n_bytes = n.to_bytes(32, byteorder='big')
    e_bytes = e.to_bytes(32, byteorder='big')
    d_bytes = d.to_bytes(32, byteorder='big')
    
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, 'public.bin'), 'wb') as f:
        f.write(n_bytes + e_bytes)
    with open(os.path.join(directory, 'private.bin'), 'wb') as f:
        f.write(n_bytes + d_bytes)

if __name__ == '__main__':
    base_dir = 'pc_key'
    
    # Read the original key's modulus (golden_n) which determines the maximum possible M size
    with open('key.bin', 'rb') as f:
        key_bytes = f.read(64)
        golden_n = int.from_bytes(key_bytes[0:32], byteorder='big')
    
    # Generate 4 completely independent, mathematically legitimate RSA keypairs
    # FPGA will ONLY trust the Public Key of the first one it talks to ('keys/').
    generate_mock_keys(os.path.join(base_dir, 'keys'), 100, golden_n)
    
    # keys1, 2, 3 are perfectly valid keys, but their signatures won't verify under keys/'s Public Key.
    generate_mock_keys(os.path.join(base_dir, 'keys1'), 101, golden_n)
    generate_mock_keys(os.path.join(base_dir, 'keys2'), 102, golden_n)
    generate_mock_keys(os.path.join(base_dir, 'keys3'), 103, golden_n)
    
    print("Real, verified RSA keys generated successfully in pc_key/")
