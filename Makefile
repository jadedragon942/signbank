build:
	docker build -t signbank .

run:
	docker run -p 8000:8000 -e DJANGO_SETTINGS_MODULE=signbank.settings -e DATABASE_URL=postgres://user:pass@host:5432/db signbank

rerun:
	docker run --rm -p 3000:3000 signbank

rerun2:
	docker run --rm -p 3000:3000 -e APP_DIR=/app/bin signbank

inspect:
	docker run --rm -it --entrypoint sh signbank -c "find /app -maxdepth 4 -name 'develop.py' -o -name 'manage.py' | cat"

wipe:
	docker ps -a | awk '{print }' | xargs -n 1 docker rm -f
