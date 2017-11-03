NAME		= node-sample
ifndef TAGS
	TAGS	= local
else
	TAGS :=$(subst /,-,$(TAGS))
endif
DOCKER_IMAGE	= $(NAME):$(TAGS)

REGISTRY	= mycluster.icp:8500/default
REGISTRY_SECRET = admin.registrykey

#REGISTRY	= registry.eu-gb.bluemix.net/cloud_native_agility_staging
#REGISTRY_SECRET = bluemix-default-secret

#REGISTRY	= 192.168.99.100:32767
#REGISTRY_SECRET =

NAMESPACE = staging-$(TAGS)

# COMMAND DEFINITIONS
BUILD		= docker build -t
TEST		= docker run --rm
TEST_CMD	= npm test
TEST_DIR	= test
VOLUME		= -v$(CURDIR)/$(TEST_DIR):/src/$(TEST_DIR)
DEPLOY		= helm
LOGIN		= docker login
PUSH		= docker push
TAG		= docker tag

.PHONY: all
all: build unittest

.PHONY: build
build: Dockerfile
	echo ">> building app as $(DOCKER_IMAGE)"
	$(BUILD) $(DOCKER_IMAGE) .
	echo ">> packaging the $DEPLOY charts"
	$(DEPLOY) lint $(NAME)-chart
	$(DEPLOY) package $(NAME)-chart

.PHONY: unittest
test:
	echo ">> running tests on $(DOCKER_IMAGE)"
	$(TEST) $(VOLUME) $(DOCKER_IMAGE) $(TEST_CMD)

.PHONY: push
push:
ifneq ($(TAGS),$(RELEASE))
	echo ">> using $(REGISTRY) registry"
	$(TAG) $(DOCKER_IMAGE) $(REGISTRY)/$(DOCKER_IMAGE)
	$(PUSH) $(REGISTRY)/$(DOCKER_IMAGE)
else
	echo ">> pushing release $(RELEASE) image to docker hub as $(DOCKER_IMAGE)"
	$(LOGIN) -u="$(DOCKER_USERNAME)" -p="$(DOCKER_PASSWORD)"
	$(PUSH) $(DOCKER_IMAGE)
endif

.PHONY: namespace
namespace:
	kubectl create ns $(NAMESPACE)
	kubectl get secret $(REGISTRY_SECRET) -o json --namespace default | sed 's/"namespace": "default"/"namespace": "$(NAMESPACE)"/g' | kubectl create -f -
	kubectl patch sa default -p '{"imagePullSecrets": [{"name": "$(REGISTRY_SECRET)"}]}' --namespace $(NAMESPACE)

.PHONY: deploy
deploy: push
	echo ">> Use $DEPLOY to install $(NAME)-chart"
	## Override the values.yaml with the target
	$(DEPLOY) install $(NAME)-chart --set image.repository=$(REGISTRY) --namespace $(NAMESPACE) --name $(NAME) --wait

.PHONY: cleankube
cleankube:
	echo ">> cleaning kube cluster for namespace $(NAMESPACE)"
	$(DEPLOY) delete $(NAME) --purge
	kubectl delete namespace $(NAMESPACE)
