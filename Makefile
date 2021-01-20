.PHONY: install server users dockertest

install:
	npm install

server:
	# # redis on port 6379
	# systemctl enable --now redis
	node server.js

dockertest:
	# yarn test runs test/users.js
	docker-compose up --build --abort-on-container-exit
