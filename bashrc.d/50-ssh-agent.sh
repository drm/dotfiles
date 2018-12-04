ssh_agent() {
	eval `ssh-agent`
	ssh-add ~/.ssh/id_rsa
}
