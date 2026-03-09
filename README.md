## Shell
```
curl -sSL https://raw.githubusercontent.com/marsjane/scripts_pub/refs/heads/main/setup_sys.sh | bash
```

## VPS
```
curl -fsSL https://raw.githubusercontent.com/marsjane/scripts_pub/refs/heads/main/vps_init.sh | bash
```
```
curl -fsSL https://raw.githubusercontent.com/marsjane/scripts_pub/refs/heads/main/vps_init.sh -o vps_init.sh
```
```
# run with root
bash vps_init.sh
# run with user
sudo -i
bash vps_init.sh --fail2ban
bash vps_init.sh --bbr
exit
sudo cp /root/vps_init.sh ./
bash vps_init.sh --shell
```
