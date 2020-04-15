VERSION=$(shell cat version.txt)
SIGN_KEY=B76D61FAA6DB759466E83D9964B9C6AAE2D55278
BINARY_NAME=statping
GOBUILD=go build -a
GOVERSION=1.14.0
XGO=xgo -go $(GOVERSION) --dest=build
BUILDVERSION=-ldflags "-X main.VERSION=${VERSION} -X main.COMMIT=$(TRAVIS_COMMIT)"
TRVIS_SECRET=O3/2KTOV8krv+yZ1EB/7D1RQRe6NdpFUEJNJkMS/ollYqmz3x2mCO7yIgIJKCKguLXZxjM6CxJcjlCrvUwibL+8BBp7xJe4XFIOrjkPvbbVPry4HkFZCf2GfcUK6o4AByQ+RYqsW2F17Fp9KLQ1rL3OT3eLTwCAGKx3tlY8y+an43zkmo5dN64V6sawx26fh6XTfww590ey+ltgQTjf8UPNup2wZmGvMo9Hwvh/bYR/47bR6PlBh6vhlKWyotKf2Fz1Bevbu0zc35pee5YlsrHR+oSF+/nNd/dOij34BhtqQikUR+zQVy9yty8SlmneVwD3yOENvlF+8roeKIXb6P6eZnSMHvelhWpAFTwDXq2N3d/FIgrQtLxsAFTI3nTHvZgs6OoTd6dA0wkhuIGLxaL3FOeztCdxP5J/CQ9GUcTvifh5ArGGwYxRxQU6rTgtebJcNtXFISP9CEUR6rwRtb6ax7h6f1SbjUGAdxt+r2LbEVEk4ZlwHvdJ2DtzJHT5DQtLrqq/CTUgJ8SJFMkrJMp/pPznKhzN4qvd8oQJXygSXX/gz92MvoX0xgpNeLsUdAn+PL9KketfR+QYosBz04d8k05E+aTqGaU7FUCHPTLwlOFvLD8Gbv0zsC/PWgSLXTBlcqLEz5PHwPVHTcVzspKj/IyYimXpCSbvu1YOIjyc=
PUBLISH_BODY='{ "request": { "branch": "master", "message": "Homebrew update version v${VERSION}", "config": { "env": { "VERSION": "${VERSION}", "COMMIT": "$(TRAVIS_COMMIT)" } } } }'
TRAVIS_BUILD_CMD='{ "request": { "branch": "master", "message": "Compile master for Statping v${VERSION}", "config": { "merge_mode": "replace", "language": "go", "install": true, "sudo": "required", "services": ["docker"], "env": { "secure": "${TRVIS_SECRET}" }, "before_deploy": ["git config --local user.name \"hunterlong\"", "git config --local user.email \"info@socialeck.com\"", "git tag v$(VERSION) --force"], "deploy": [{ "provider": "releases", "api_key": "$$GITHUB_TOKEN", "file_glob": true, "file": "build/*", "skip_cleanup": true, "on": { "branch": "master" } }], "before_script": ["rm -rf ~/.nvm && git clone https://github.com/creationix/nvm.git ~/.nvm && (cd ~/.nvm && git checkout `git describe --abbrev=0 --tags`) && source ~/.nvm/nvm.sh && nvm install stable", "nvm install 10.17.0", "nvm use 10.17.0 --default", "npm install -g sass yarn cross-env", "pip install --user awscli"], "script": ["make release"], "after_success": [], "after_deploy": ["make post-release"] } } }'
TEST_DIR=$(GOPATH)/src/github.com/statping/statping
PATH:=/usr/local/bin:$(GOPATH)/bin:$(PATH)
OS = darwin freebsd linux openbsd
ARCHS = 386 arm amd64 arm64

all: clean yarn-install compile docker-base docker-vue build-all

up:
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml up -d --remove-orphans
	make print_details

down:
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml down --volumes --remove-orphans

lite: clean
	docker build -t statping/statping:dev -f dev/Dockerfile.dev .
	docker-compose -f dev/docker-compose.lite.yml down
	docker-compose -f dev/docker-compose.lite.yml up --remove-orphans

reup: down clean compose-build-full up

test: clean compile
	go test -v -p=1 -ldflags="-X main.VERSION=testing" -coverprofile=coverage.out ./...

# build all arch's and release Statping
release: test-deps
	wget -O statping.gpg $(SIGN_URL)
	gpg --import statping.gpg
	make build-all

test-ci: clean compile test-deps
	SASS=`which sass` go test -v -covermode=count -coverprofile=coverage.out -p=1 ./...
	goveralls -coverprofile=coverage.out -service=travis-ci -repotoken ${COVERALLS}

cypress: clean
	echo "Statping Bin: "`which statping`
	echo "Statping Version: "`statping version`
	cd frontend && yarn test
	killall statping

test-api:
	DB_CONN=sqlite DB_HOST=localhost DB_DATABASE=sqlite DB_PASS=none DB_USER=none statping &
	sleep 5000 && newman run source/tmpl/postman.json -e dev/postman_environment.json --delay-request 500

test-deps:
	go get golang.org/x/tools/cmd/cover
	go get github.com/mattn/goveralls
	go get github.com/GeertJohan/go.rice/rice

deps:
	go get -d -v -t ./...

protoc:
	cd types/proto && protoc --gofast_out=plugins=grpc:. statping.proto

yarn-serve:
	cd frontend && yarn serve

yarn-install:
	cd frontend && rm -rf node_modules && yarn

go-run:
	go run ./cmd

start:
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml start

stop:
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml stop

logs:
	docker logs statping --follow

db-up:
	docker-compose -f dev/docker-compose.db.yml up -d --remove-orphans

db-down:
	docker-compose -f dev/docker-compose.full.yml down --remove-orphans

console:
	docker exec -t -i statping /bin/sh

compose-build-full: docker-base
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml build --parallel --build-arg VERSION=${VERSION}

docker-base:
	docker build -t statping/statping:base -f Dockerfile.base --build-arg VERSION=${VERSION} .

docker-latest: docker-base
	docker build -t statping/statping:latest --build-arg VERSION=${VERSION} .

docker-vue:
	docker build -t statping/statping:vue --build-arg VERSION=${VERSION} .

docker-test:
	docker-compose -f docker-compose.test.yml up --remove-orphans

push-base: clean compile docker-base
	docker push statping/statping:base

push-vue: clean compile docker-base docker-vue
	docker push statping/statping:base
	docker push statping/statping:vue

modd:
	modd -f ./dev/modd.conf

top:
	docker-compose -f docker-compose.yml -f dev/docker-compose.full.yml top

frontend-build:
	rm -rf source/dist && rm -rf frontend/dist
	cd frontend && yarn && yarn build
	cp -r frontend/dist source/ && cp -r frontend/src/assets/scss source/dist/
	cp -r source/tmpl/*.* source/dist/

frontend-copy:
	cp -r source/tmpl/*.* source/dist/

yarn:
	rm -rf source/dist && rm -rf frontend/dist
	cd frontend && yarn

# compile assets using SASS and Rice. compiles scss -> css, and run rice embed-go
compile: frontend-build
	rm -f source/rice-box.go
	cd source && rice embed-go

embed:
	cd source && rice embed-go

build:
	$(GOBUILD) $(BUILDVERSION) -o $(BINARY_NAME) ./cmd

install: build
	mv $(BINARY_NAME) $(GOPATH)/bin/$(BINARY_NAME)

install-local: build
	mv $(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)

generate:
	cd source && go generate

build-bin:
	mkdir build
	export PWD=`pwd`
	@for arch in $(ARCHS);\
	do \
		for os in $(OS);\
		do \
			echo "Building $$os-$$arch"; \
			mkdir -p releases/statping-$$os-$$arch/; \
			GOOS=$$os GOARCH=$$arch go build -a -ldflags "-X main.VERSION=${VERSION} -X main.COMMIT=$(TRAVIS_COMMIT)" -o releases/statping-$$os-$$arch/statping ${PWD}/cmd; \
			chmod +x releases/statping-$$os-$$arch/statping; \
			tar -czf releases/statping-$$os-$$arch.tar.gz -C releases/statping-$$os-$$arch statping; \
		done \
	done
	find ./releases/ -name "*.tar.gz" -type f -size +1M -exec mv "{}" build/ \;

build-win:
	export PWD=`pwd`
	@for arch in $(ARCHS);\
	do \
		echo "Building windows-$$arch"; \
		mkdir -p releases/statping-windows-$$arch/; \
		GOOS=windows GOARCH=$$arch go build -a -ldflags "-X main.VERSION=${VERSION} -X main.COMMIT=$(TRAVIS_COMMIT)" -o releases/statping-windows-$$arch/statping.exe ${PWD}/cmd; \
		chmod +x releases/statping-windows-$$arch/statping.exe; \
		zip -j releases/statping-windows-$$arch.zip releases/statping-windows-$$arch/statping.exe || true; \
	done
	find ./releases/ -name "*.zip" -type f -size +1M -exec mv "{}" build/ \;

# remove files for a clean compile/build
clean:
	rm -rf ./{logs,assets,plugins,*.db,config.yml,.sass-cache,config.yml,statping,build,.sass-cache,index.html,vendor}
	rm -rf cmd/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log,*.html,*.json}
	rm -rf core/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf types/notifications/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf handlers/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf notifiers/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf source/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf types/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf utils/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf frontend/{logs,plugins,*.db,config.yml,.sass-cache,*.log}
	rm -rf dev/{logs,assets,plugins,*.db,config.yml,.sass-cache,*.log,test/app,plugin/*.so}
	rm -rf {parts,prime,snap,stage}
	rm -rf dev/test/cypress/videos
	rm -f coverage.* sass
	rm -f source/rice-box.go
	rm -rf **/*.db-journal
	rm -rf *.snap
	find . -name "*.out" -type f -delete
	find . -name "*.cpu" -type f -delete
	find . -name "*.mem" -type f -delete
	rm -rf {build,releases,tmp}

print_details:
	@echo \==== Statping Development Instance ====
	@echo \Statping Vue Frontend:     http://localhost:8888
	@echo \Statping Backend API:      http://localhost:8585
	@echo \==== Statping Instances ====
	@echo \Statping SQLite:     http://localhost:4000
	@echo \Statping MySQL:      http://localhost:4005
	@echo \Statping Postgres:   http://localhost:4010
	@echo \==== Databases ====
	@echo \PHPMyAdmin:          http://localhost:6000  \(MySQL database management\)
	@echo \SQLite Web:          http://localhost:6050  \(SQLite database management\)
	@echo \PGAdmin:             http://localhost:7000  \(Postgres database management \| email: admin@admin.com password: admin\)
	@echo \Prometheus:          http://localhost:7050  \(Prometheus Web UI\)
	@echo \==== Monitoring and IDE ====
	@echo \Grafana:             http://localhost:3000  \(username: admin, password: admin\)

build-all: clean compile build-bin build-win

coverage: test-deps
	$(GOPATH)/bin/goveralls -coverprofile=coverage.out -service=travis -repotoken $(COVERALLS)

# build Statping using a travis ci trigger
travis-build: travis_s3_creds
	curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -H "Travis-API-Version: 3" -H "Authorization: token $(TRAVIS_API)" -d $(TRAVIS_BUILD_CMD) https://api.travis-ci.com/repo/statping%2Fstatping/requests
	curl -H "Content-Type: application/json" --data '{"docker_tag": "latest"}' -X POST $(DOCKER)

download-key:
	wget -O statping.gpg $(SIGN_URL)
	gpg --import statping.gpg

# build :latest docker tag
docker-build-latest:
	docker build --build-arg VERSION=${VERSION} -t statping/statping:latest --no-cache -f Dockerfile .
	docker tag statping/statping:latest statping/statping:v${VERSION}

# push the :dev docker tag using curl
publish-dev:
	curl -H "Content-Type: application/json" --data '{"docker_tag": "dev"}' -X POST $(DOCKER)

publish-latest: publish-base
	curl -H "Content-Type: application/json" --data '{"docker_tag": "latest"}' -X POST $(DOCKER)

publish-base:
	curl -H "Content-Type: application/json" --data '{"docker_tag": "base"}' -X POST $(DOCKER)

post-release: frontend-build upload_to_s3 publish-homebrew publish-latest

# update the homebrew application to latest for mac
publish-homebrew:
	curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -H "Travis-API-Version: 3" -H "Authorization: token $(TRAVIS_API)" -d $(PUBLISH_BODY) https://api.travis-ci.com/repo/statping%2Fhomebrew-statping/requests

upload_to_s3: travis_s3_creds
	aws s3 cp ./source/dist/css $(ASSETS_BKT) --recursive --exclude "*" --include "*.css"
	aws s3 cp ./source/dist/js $(ASSETS_BKT) --recursive --exclude "*" --include "*.js"
	aws s3 cp ./source/dist/scss $(ASSETS_BKT) --recursive --exclude "*" --include "*.scss"
	aws s3 cp ./install.sh $(ASSETS_BKT)

travis_s3_creds:
	mkdir -p ~/.aws
	echo "[default]\naws_access_key_id = ${AWS_ACCESS_KEY_ID}\naws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}" > ~/.aws/credentials

sign-all:
	gpg --default-key $SIGN_KEY --detach-sign --armor statpinger

valid-sign:
	gpg --verify statping.asc

# install xgo and pull the xgo docker image
xgo-install: clean
	go get github.com/crazy-max/xgo
	docker pull crazymax/xgo:${GOVERSION}

sentry-release:
	sentry-cli releases new -p backend -p frontend v${VERSION}
	sentry-cli releases set-commits --auto v${VERSION}
	sentry-cli releases finalize v${VERSION}

snapcraft: clean snapcraft-build snapcraft-release

snapcraft-build: build-all
	PWD=$(shell pwd)
	cp build/$(BINARY_NAME)-linux-x64.tar.gz build/$(BINARY_NAME)-linux.tar.gz
	snapcraft clean statping -s pull
	docker run --rm -v ${PWD}:/build -w /build --env VERSION=${VERSION} snapcore/snapcraft bash -c "apt update && snapcraft --target-arch=amd64"
	cp build/$(BINARY_NAME)-linux-x32.tar.gz build/$(BINARY_NAME)-linux.tar.gz
	snapcraft clean statping -s pull
	docker run --rm -v ${PWD}:/build -w /build --env VERSION=${VERSION} snapcore/snapcraft bash -c "apt update && snapcraft --target-arch=i386"
	cp build/$(BINARY_NAME)-linux-arm64.tar.gz build/$(BINARY_NAME)-linux.tar.gz
	snapcraft clean statping -s pull
	docker run --rm -v ${PWD}:/build -w /build --env VERSION=${VERSION} snapcore/snapcraft bash -c "apt update && snapcraft --target-arch=arm64"
	cp build/$(BINARY_NAME)-linux-arm7.tar.gz build/$(BINARY_NAME)-linux.tar.gz
	snapcraft clean statping -s pull
	docker run --rm -v ${PWD}:/build -w /build --env VERSION=${VERSION} snapcore/snapcraft bash -c "apt update && snapcraft --target-arch=armhf"
	rm -f build/$(BINARY_NAME)-linux.tar.gz

snapcraft-release:
	snapcraft push statping_${VERSION}_arm64.snap --release stable
	snapcraft push statping_${VERSION}_i386.snap --release stable
	snapcraft push statping_${VERSION}_armhf.snap --release stable

.PHONY: all build build-all build-alpine test-all test test-api docker frontend up down print_details lite sentry-release
.SILENT: travis_s3_creds
