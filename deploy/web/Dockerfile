# The web export as a container image: nginx serving front/build/web. Run `just export-web`
# first, then build from the repo root:
#   docker build -f deploy/web/Dockerfile -t webgame-web .
FROM nginx:1.27-alpine
COPY deploy/web/default.conf /etc/nginx/conf.d/default.conf
COPY front/build/web /usr/share/nginx/html
# Compress the big files once, at build time, so nginx can send the .gz copy to browsers that
# accept it (gzip_static) instead of compressing 40+ MB on every request. -k keeps the originals
# for clients that don't.
RUN cd /usr/share/nginx/html && gzip -k -9 *.wasm *.js *.pck
