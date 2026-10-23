class_name BrightwingKey
extends RefCounted

## Brightwing's island-signing PUBLIC key, compiled into the game (contract §5). Release builds
## load an installed island pack only if its signature checks against this key.
##
## Brightwing's real key (made by the human, 2026-10-21; the private half is in the signer's private key file (never in the repo)). It
## also signs the official scene packages (`just pack`, contract §8). To replace it:
##   1. just island-key <a folder outside the repo>   (writes a private and a public PEM)
##   2. put the private PEM in the signer's private key file (never in the repo), never in the repo, and delete the file;
##   3. paste the public PEM below in place of the placeholder text and commit it.
## The private key never enters the repo; the public one is meant to be public.

const PEM := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5UtbqYzILJpSrJVGULFf
09159Ey44IWSpP56oz5wvxf15JSqVcj3wMsqXg+/dfDU7vUrqQrPPTRyn+Ml4VPh
gF/Kp2+4OvZf70Avutd6SJJU5zJPLIMvxBMiYJ0V/rz9NnUfjpU8G35XhDPRbVBQ
NGVDzTPRjwP5Zc7HnukcdNpP2RXV6isiOhDGeaX0YQdTwMNt6X04HsGzgLC9YplZ
vORdyzocxxDsF5wv69HL+4QsQteZmXthKE4OAYeJ9pByoPXKnYKkfjjlrfuK/Bkd
z+0d7W/Aeo1VI2TTMgN4pZXy1CzkBQ8bcdxM+pe+2RFSyBhe+n6NK+ZHnyFwAiOT
/wIDAQAB
-----END PUBLIC KEY-----"""
