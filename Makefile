SHELL := /usr/bin/env bash

.PHONY: help configure check init fmt validate plan apply deploy inventory ansible status dns rdns backup restore update destroy clean

help:
	@./pfif help
configure:
	@./pfif configure
check:
	@./pfif check
init:
	@./pfif init
fmt:
	@./pfif fmt
validate:
	@./pfif validate
plan:
	@./pfif plan
apply:
	@./pfif apply
deploy:
	@./pfif deploy
inventory:
	@./pfif inventory
ansible:
	@./pfif ansible
status:
	@./pfif status
dns:
	@./pfif dns
rdns:
	@./pfif rdns
backup:
	@./pfif backup
restore:
	@test -n "$(BACKUP)" || (echo 'Usage: make restore BACKUP=/path/to/backup' >&2; exit 2)
	@./pfif restore "$(BACKUP)"
update:
	@./pfif update
destroy:
	@./pfif destroy
clean:
	@rm -rf tofu/environments/prod/.terraform tofu/environments/prod/.terraform.lock.hcl artifacts .tmp
