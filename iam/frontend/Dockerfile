FROM python:3.12-slim
WORKDIR /app
COPY serve.py index.html ./
EXPOSE 3000
ENV PORT=3000
CMD ["python3", "-u", "serve.py"]
