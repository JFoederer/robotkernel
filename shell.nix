{ pkgs ? import ./nix {}
, sikuli ? false
, vim ? false
}:

let self = rec {

  # python packages

  python = (import ./setup.nix {
    inherit pkgs;
    pythonPackages = pkgs.python3Packages;
  }).targetPython;

  pythonPackages = python.pkgs;

  sikulilibrary = (import ./pkgs/sikulixlibrary {
    inherit pkgs pythonPackages;
    jdk = pkgs.jdk;
    sikulix = with pkgs; import ./pkgs/sikulix {
      inherit stdenv fetchurl makeWrapper utillinux jre jdk opencv;
      inherit tesseract xdotool wmctrl;
    };
  });

  "robotkernel" = (import ./setup.nix {
    inherit pkgs;
    pythonPackages = pkgs.python3Packages;
  }).package;

  # other packages

  vim_binding = pkgs.fetchFromGitHub {
    owner = "lambdalisue";
    repo = "jupyter-vim-binding";
    rev = "c9822c753b6acad8b1084086d218eb4ce69950e9";
    sha256 = "1951wnf0k91h07nfsz8rr0c9nw68dbyflkjvw5pbx9dmmzsa065j";
  };

  # jupyter

  jupyter = pythonPackages.jupyter.overridePythonAttrs (old: {
    propagatedBuildInputs =
    with pythonPackages; old.propagatedBuildInputs ++ [
      (graphviz.overridePythonAttrs(old: { doCheck = false; }))
      iplantuml
      ipywidgets
      jupytext
      jupyter-starters
      jupyter-contrib-nbextensions
      jupyter-nbextensions-configurator
      jupyterlab
      jupyterlab-kernelspy
      nbimporter
      opencv3
      RESTinstance
      matplotlib
      rise
      robotframework
#     robotframework-appiumlibrary
      robotframework-faker
      robotframework-seleniumlibrary
      robotframework-seleniumtestability
      robotframework-seleniumscreenshots
      robotframework-jupyterlibrary
      robotframework-sshlibrary
      robotkernel
      tkinter
      widgetsnbextension
    ] ++ pkgs.lib.optionals sikuli [ sikulilibrary ];
  });

  jupyter_nbconfig = pkgs.stdenv.mkDerivation rec {
    name = "jupyter";
    json = builtins.toJSON {
      load_extensions = {
        "jupyter-js-widgets/extension" = true;
        "rise/main" = true;
        "jupytext/index" = true;
        "vim_binding/vim_binding" = if vim then true else false;
      };
      keys = {
        command = {
          bind = {
            "Ctrl-7" = "RISE:toggle-slide";
            "Ctrl-8" = "RISE:toggle-subslide";
            "Ctrl-9" = "RISE:toggle-fragment";
          };
        };
      };
    };
    builder = with pkgs; builtins.toFile "builder.sh" ''
      source $stdenv/setup
      mkdir -p $out
      cat > $out/notebook.json << EOF
      $json
      EOF
    '';
  };

  jupyter_config_dir = pkgs.stdenv.mkDerivation {
    name = "jupyter";
    builder = with pythonPackages; with pkgs; writeText "builder.sh" ''
      source $stdenv/setup
      mkdir -p $out/share/jupyter/nbextensions
      mkdir -p $out/share/jupyter/migrated
      mkdir -p $out/share/jupyter/jupyter_notebook_config.d

      ln -s ${jupyter_nbconfig} $out/share/jupyter/nbconfig
      ln -s ${jupyter-contrib-nbextensions}/${python.sitePackages}/jupyter-contrib-nbextensions/nbextensions/* $out/share/jupyter/nbextensions
      ln -s ${rise}/${python.sitePackages}/rise/static $out/share/jupyter/nbextensions/rise
      ln -s ${vim_binding} $out/share/jupyter/nbextensions/vim_binding
      ln -s ${widgetsnbextension}/share/jupyter/nbextensions/* $out/share/jupyter/nbextensions

      ${python.withPackages (ps: with ps; [ robotkernel ])}/bin/python -m robotkernel.install --prefix=$out
      cp -R ${python.withPackages (ps: with ps; [ robotkernel ])}/etc/jupyter/jupyter_notebook_config.d/* $out/share/jupyter/jupyter_notebook_config.d

      JUPYTER_CONFIG_DIR=$out/share/jupyter \
      PATH=${python.withPackages (ps: with ps; [ jupyter-starters ])}/bin \
      ${python.withPackages (ps: with ps; [ jupyter-starters ])}/bin/jupyter serverextension enable --py jupyter_starters

      JUPYTER_CONFIG_DIR=$out/share/jupyter \
      PATH=${python.withPackages (ps: with ps; [ notebook jupytext ])}/bin \
      ${python.withPackages (ps: with ps; [ notebook jupytext ])}/bin/jupyter serverextension enable jupytext

      echo "import rise" >> $out/share/jupyter/jupyter_notebook_config.py

      cat > $out/share/jupyter/jupyter_nbconvert_config.py << EOF
      c = get_config()
      c.Exporter.preprocessors = ['jupyter_contrib_nbextensions.nbconvert_support.pre_pymarkdown.PyMarkdownPreprocessor']
      EOF
    '';
  };
};

in with self;

pkgs.stdenv.mkDerivation rec {
  name = "jupyter";
  env = pkgs.buildEnv { name = name; paths = buildInputs; };
  builder = builtins.toFile "builder.sh" ''
    source $stdenv/setup; ln -s $env $out
  '';
  buildInputs = [
    pkgs.nodejs
    pkgs.firefox
    pkgs.geckodriver
    jupyter
    jupyter_config_dir
  ] ++ (with pkgs; lib.optionals stdenv.isLinux [ bash fontconfig tini ])
    ++ (with pkgs; lib.optionals sikuli [ jre8 ]);
  shellHook = ''
    mkdir -p $(pwd)/.jupyter
    chmod u+w -R $(pwd)/.jupyter
    cp -R ${jupyter_config_dir}/share/jupyter/* $(pwd)/.jupyter
    export JUPYTER_CONFIG_DIR=$(pwd)/.jupyter
    export JUPYTER_PATH=$(pwd)/.jupyter
    export JUPYTER_DATA_DIR=$(pwd)/.jupyter
    export JUPYTER_RUNTIME_DIR=$(pwd)/.jupyter
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
  '';
}
