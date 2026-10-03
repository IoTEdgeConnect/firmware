# Certificate Material

This directory holds the TLS credentials required to connect to AWS IoT Core.
All three files are listed in `.gitignore` and must **never** be committed.

## Required files

| File | Description |
|---|---|
| `device.crt` | Device certificate issued by AWS IoT Core |
| `device.key` | Device private key — keep this secret |
| `root-ca.pem` | Amazon Root CA 1 (public, but excluded for consistency) |

## Obtaining the files

Follow [`infrastructure/docs/device-provisioning.md`](../../../../infrastructure/docs/device-provisioning.md)
in the `infrastructure` repository.

1. Download the device certificate and private key from the AWS IoT Core console
   at the moment of certificate creation (the private key cannot be re-downloaded).
2. Download **Amazon Root CA 1** from:
   <https://www.amazontrust.com/repository/AmazonRootCA1.pem>
3. Place all three files in this directory with the exact names above.

## Build behaviour

The firmware CMakeLists embeds these files into the binary using
`target_add_binary_data`. If any file is absent the build will fail with a
clear CMake error rather than silently embedding empty credentials.

## CI

CI uses placeholder certificate stubs (`tests/certs/`) so the build compiles
without real credentials. The placeholder files contain no usable key material.
