FROM ruby:2.4.2

RUN gem install bundler --version "1.16.0" --force

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

RUN useradd -m appuser -d /home/app
RUN chown -R appuser:appuser /usr/local/bundle

COPY . /home/app/www
RUN chown -R appuser:appuser /home/app/www

USER appuser
ENV HOME /home/app

WORKDIR /home/app/www
