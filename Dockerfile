# Use the Ruby 2.7.1 image from Docker Hub
# as the base image (https://hub.docker.com/_/ruby)
FROM ruby:2.7.2

# Use a directory called /code in which to store
# this application's files. (The directory name
# is arbitrary and could have been anything.)
WORKDIR /code

# Copy all the application's files into the /code
# directory.
COPY . /code

# Run bundle install to install the Ruby dependencies.
RUN bundle install

# Commmand to run when this container starts.
CMD ["bundle", "exec", "puma", "-t", "5:5", "-p", "${PORT:-3000}", "-e", "${RACK_ENV:-development}"]
