SHELL := /bin/bash
CONDA   := ~/miniconda3/bin/conda
VIPE_ENV := vipe
GS_ENV   := gaussian_splatting
VIPE_RUN := $(CONDA) run --no-capture-output -n $(VIPE_ENV) --
GS_RUN   := $(CONDA) run --no-capture-output -n $(GS_ENV) --

VIDEO      ?= /root/gaussian-splatting/output.mp4
SEQUENCE   ?= output
RESULT_DIR ?= $(CURDIR)/results

install:
	wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
	bash /tmp/miniconda.sh -b -u -p ~/miniconda3 && rm /tmp/miniconda.sh
	git clone https://github.com/nv-tlabs/vipe.git
	git clone https://github.com/graphdeco-inria/gaussian-splatting --recursive
	
	cd vipe && $(CONDA) env create -n $(VIPE_ENV) -f envs/base.yml
	$(VIPE_RUN) pip install --no-cache-dir -r vipe/envs/requirements.txt --extra-index-url https://download.pytorch.org/whl/cu128
	$(VIPE_RUN) pip install --no-cache-dir --no-build-isolation -e vipe
	$(VIPE_RUN) pip install "git+https://github.com/microsoft/MoGe.git"
	$(VIPE_RUN) pip install "huggingface-hub<1.0"

	$(CONDA) tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
	$(CONDA) tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
	$(CONDA) create -n $(GS_ENV) python=3.10 -y
	$(GS_RUN) pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
	$(GS_RUN) pip install plyfile tqdm opencv-python-headless
	$(GS_RUN) pip install --no-build-isolation -e gaussian-splatting/submodules/diff-gaussian-rasterization
	$(GS_RUN) pip install --no-build-isolation --force-reinstall --no-cache-dir gaussian-splatting/submodules/simple-knn

vipe:
	HYDRA_FULL_ERROR=1 $(VIPE_RUN) python vipe/run.py \
		pipeline=lyra \
		streams=raw_mp4_stream \
		streams.base_path=$(VIDEO) \
		pipeline.output.save_artifacts=true \
		pipeline.output.path=vipe/vipe_results \
		pipeline.output.save_slam_map=true
	$(VIPE_RUN) python vipe/scripts/vipe_to_colmap.py vipe/vipe_results --sequence $(SEQUENCE) --use_slam_map
	mkdir -p vipe/vipe_results_colmap/$(SEQUENCE)/sparse/0
	mv -n vipe/vipe_results_colmap/$(SEQUENCE)/{cameras,images,points3D}.txt vipe/vipe_results_colmap/$(SEQUENCE)/sparse/0/ 2>/dev/null || true
	sed -i 's|images/||g' vipe/vipe_results_colmap/output/sparse/0/images.txt


visualize:
	$(VIPE_RUN) vipe visualize vipe/vipe_results/ -p 8888


train:
	$(GS_RUN) python gaussian-splatting/train.py \
		-s vipe/vipe_results_colmap/$(SEQUENCE) \
		-m $(RESULT_DIR) \
		--iterations 20000 \
		--position_lr_max_steps 30000 \
		--densify_until_iter 15000 \
		--densify_grad_threshold 0.0005 \
		--opacity_reset_interval 3000 \
		--antialiasing \
		--eval

render:
	$(GS_RUN) python gaussian-splatting/render.py -m $(RESULT_DIR) -s vipe/vipe_results_colmap/$(SEQUENCE)

metrics:
	$(GS_RUN) python gaussian-splatting/metrics.py -m $(RESULT_DIR)

all: vipe train render metrics

clean: clean
	rm -rf vipe gaussian-splatting results
	$(CONDA) env remove -n $(VIPE_ENV) -y 2>/dev/null || true
	$(CONDA) env remove -n $(GS_ENV) -y 2>/dev/null || true

.PHONY: install vipe visualize train render clean_results all clean
