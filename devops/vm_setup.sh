sudo adduser devgogo
sudo usermod -aG sudo devgogo
sudo ufw allow OpenSSH
sudo ufw enable

# Optional (if root logged in via SSH)
rsync --archive --chown=devgogo:devgogo ~/.ssh /home/devgogo

# Setup docker
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install docker
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Run docker without sudo
sudo usermod -aG docker ${USER}
echo "alias docker='sudo docker'" >> ~/.bash_aliases

# Install node
sudo apt update
sudo apt install nodejs
sudo apt install npm
sudo npm install -g yarn

# Git
ssh-keygen -t ed25519
# cat ~/.ssh/id_ed25519.pub # copy this to github dev settings
# git clone git@github.com:...
