# Simple demo Dockerfile for HNG Stage 1
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 5000
