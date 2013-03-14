SHELL = /bin/bash
BEAKER = beaker-branches/master
SPHINXBUILD = $(shell command -v sphinx-1.0-build sphinx-build)
SPHINXBUILDOPTS =

# Symbolic targets defined in this Makefile:
# 	all-docs: 	all branches of the Sphinx docs from Beaker git
# 	all-website: 	all the web site bits, *except* yum repos
# 	all:		all of the above, plus yum repos
.PHONY: all
all: all-docs all-website yum

ARTICLES = COPYING.html dev-guide.html tech-roadmap.html cobbler-migration.html

include releases.mk
OLD_TARBALLS = \
    releases/beaker-0.6.16.tar.bz2 \
    releases/beaker-0.6.1.tar.gz \
    releases/beaker-0.6.1.tar.bz2 \
    releases/beaker-0.5.7.tar.bz2 \
    releases/beaker-0.4.75.tar.bz2 \
    releases/beaker-0.4.3.tar.bz2 \
    releases/beaker-0.4.tar.bz2

include docs.mk # defines all-docs target

# treat warnings as errors only for the released docs
docs: SPHINXBUILDOPTS += -W

.PHONY: all-website
all-website: \
     server-api \
     man \
     dev \
     schema/beaker-job.rng \
     releases/SHA1SUM \
     releases/index.html \
     releases/index.atom \
     $(DOWNLOADS) \
     $(OLD_TARBALLS) \
     in-a-box/beaker.ks.html \
     in-a-box/beaker-setup.html \
     in-a-box/beaker-distros.html \
     in-a-box/beaker-virt.html \
     $(ARTICLES)

# XXX delete and redirect server-api and man when 0.12 is released

server-api::
	$(MAKE) -C $(BEAKER)/Common bkr/__init__.py
	env BEAKER=$(abspath $(BEAKER)) PYTHONPATH=$(BEAKER)/Common:$(BEAKER)/Server \
	python -c '__requires__ = ["TurboGears"]; import pkg_resources; execfile("$(SPHINXBUILD)")' \
	$(SPHINXBUILDOPTS) -c $@ -b html $(BEAKER)/Server/apidoc/ $@/

man::
	$(MAKE) -C $(BEAKER)/Common bkr/__init__.py
	env BEAKER=$(abspath $(BEAKER)) PYTHONPATH=$(BEAKER)/Common:$(BEAKER)/Client/src \
	$(SPHINXBUILD) $(SPHINXBUILDOPTS) -c $@ -b html $(BEAKER)/Client/doc/ $@/

docs.mk: beaker-branches generate-docs-mk.sh
	./generate-docs-mk.sh >$@

.PHONY: dev
dev: SPHINXBUILDOPTS += -W
dev:
	$(SPHINXBUILD) $(SPHINXBUILDOPTS) -c $@ -b html ./dev/ $@/

schema/beaker-job.rng: $(BEAKER)/Common/bkr/common/schema/beaker-job.rng
	mkdir -p $(dir $@)
	cp -p $< $@

releases.mk: $(BEAKER)/beaker.spec generate-releases-mk.py changelog.py
	./generate-releases-mk.py <$< >$@

releases/index.html: $(BEAKER)/beaker.spec releases/SHA1SUM generate-releases-index.py changelog.py
	mkdir -p $(dir $@)
	./generate-releases-index.py --format=html $< >$@

releases/index.atom: $(BEAKER)/beaker.spec releases/SHA1SUM generate-releases-index.py changelog.py
	mkdir -p $(dir $@)
	./generate-releases-index.py --format=atom $< >$@

$(OLD_TARBALLS):
	mkdir -p $(dir $@)
	cd $(dir $@) && curl -# -R -f -O http://beaker-project.org/$@

# Release artefacts (tarballs and patches) must never change once they have 
# been published. So when "building" one, we always first try to grab it from 
# the public web site in case it has already been published. Only if it doesn't 
# exist should we *actually* build it from scratch here.

releases/%.tar.gz:
	mkdir -p $(dir $@)
	@echo "Trying to fetch release artefact $@" ; \
	curl -# -R -f -o$@ http://beaker-project.org/$@ ; result=$$? ; \
	if [ $$result -ne 22 ] ; then exit $$result ; fi ; \
	echo "Release artefact $@ not published, building it" ; \
	( cd $(BEAKER) && flock /tmp/tito tito build --tgz --tag=$*-1 ) && cp /tmp/tito/$*.tar.gz $@

releases/%.tar.xz: releases/%.tar.gz
	mkdir -p $(dir $@)
	@echo "Trying to fetch release artefact $@" ; \
	curl -# -R -f -o$@ http://beaker-project.org/$@ ; result=$$? ; \
	if [ $$result -ne 22 ] ; then exit $$result ; fi ; \
	echo "Release artefact $@ not published, building it" ; \
	gunzip -c $< | xz >$@

releases/%.patch:
	mkdir -p $(dir $@)
	@echo "Trying to fetch release artefact $@" ; \
	curl -# -R -f -o$@ http://beaker-project.org/$@ ; result=$$? ; \
	if [ $$result -ne 22 ] ; then exit $$result ; fi ; \
	echo "Release artefact $@ not published, building it" ; \
	( cd $(BEAKER) && flock /tmp/tito tito build --tgz --tag=$* ) && cp /tmp/tito/$*.patch $@

releases/SHA1SUM: $(DOWNLOADS) $(OLD_TARBALLS) releases.mk
	mkdir -p $(dir $@)
	( cd $(dir $@) && ls -rv $(notdir $(DOWNLOADS)) $(notdir $(OLD_TARBALLS)) | xargs sha1sum ) >$@

yum::
	./build-yum-repos.py --config yum-repos.conf --dest $@

in-a-box/%.html: in-a-box/% shocco.sh
	./shocco.sh $< >$@

# This is annoying... at some point pandoc started ignoring the -5 option,
# instead you have to specify -t html5 to select HTML5 output.
PANDOC_OUTPUT_OPTS := $(if $(shell pandoc --help | grep 'Output formats:.*html5'),-t html5,-t html -5)

%.html: %.txt pandoc-header.html pandoc-before-body.html pandoc-after-body.html pandoc-fixes.py
	pandoc -f markdown $(PANDOC_OUTPUT_OPTS) --standalone --section-divs \
	    --smart --variable=lang=en --css=style.css \
	    --include-in-header=pandoc-header.html \
	    --toc \
	    --include-before-body=pandoc-before-body.html \
	    --include-after-body=pandoc-after-body.html \
	    <$< | ./pandoc-fixes.py >$@

.PHONY: check
check:
# ideas: spell check everything, validate HTML, check for broken links, run sphinx linkcheck builder
	./check-yum-repos.py
