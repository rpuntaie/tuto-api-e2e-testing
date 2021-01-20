
.. https://www.freecodecamp.org/news/end-to-end-api-testing-with-docker/

API end to tend testing with Docker
===================================

Testing is a pain in general. Some don't see the point. Some see it but
think of it as an extra step slowing them down. Sometimes tests are
there but very long to run or unstable. In this article you'll see how
you can engineer tests for yourself with Docker.

We want fast, meaningful and reliable tests written and maintained with
minimal effort. It means tests that are useful to you as a developer on
a day-to-day basis. They should boost your productivity and improve the
quality of your software. Having tests because everybody says  "you
should have tests" is no good if it slows you down.

Let's see how to achieve this with not that much effort.

The example we are going to test
--------------------------------

In this article we are going to test an API built with Node/express and
use chai/mocha for testing. I've chosen a JS'y stack because the code is
super short and easy to read. The principles applied are valid for any
tech stack. Keep reading even if Javascript makes you sick.

The example will cover a simple set of CRUD endpoints for users. It's
more than enough to grasp the concept and apply to the more complex
business logic of your API.

We are going to use a pretty standard environment for the API:

-  A Postgres database
-  A Redis cluster
-  Our API will use other external APIs to do its job

Your API might need a different environment. The principles applied in
this article will remain the same. You'll use different Docker base
images to run whatever component you might need.

Why Docker? And in fact Docker Compose
--------------------------------------

This section contains a lot of arguments in favour of using Docker for
testing. You can skip it if you want to get to the technical part right
away.

The painful alternatives
------------------------

To test your API in a close to production environment you have two
choices. You can mock the environment at code level or run the tests on
a real server with the database etc. installed.

Mocking everything at code level clutters the code and configuration of
our API. It is also often not very representative of how the API will
behave in production. Running the thing in a real server is
infrastructure heavy. It is a lot of setup and maintenance, and it does
not scale. Having a shared database, you can run only 1 test at a time
to ensure test runs do not interfere with each other.

Docker Compose allows us to get the best of both worlds. It creates
"containerized" versions of all the external parts we use. It is mocking
but on the outside of our code. Our API thinks it is in a real physical
environment. Docker compose will also create an isolated network for all
the containers for a given test run. This allows you to run several of
them in parallel on your local computer or a CI host.

Overkill?
---------

You might wonder if it isn't overkill to perform end to end tests at all
with Docker compose. What about just running unit tests instead?

For the last 10 years, large monolith applications have been split into
smaller services (trending towards the buzzy "microservices"). A given
API component relies on more external parts (infrastructure or other
APIs). As services get smaller, integration with the infrastructure
becomes a bigger part of the job.

You should keep a small gap between your production and your development
environments. Otherwise problems will arise when going for production
deploy. By definition these problems appear at the worst possible
moment. They will lead to rushed fixes, drops in quality, and
frustration for the team. Nobody wants that.

You might wonder if end to end tests with Docker compose run longer than
traditional unit tests. Not really. You'll see in the example below that
we can easily keep the tests under 1 minute, and at great benefit: the
tests reflect the application behaviour in the real world. This is more
valuable than knowing if your class somewhere in the middle of the app
works OK or not.

Also, if you don't have any tests right now, starting from end to end
gives you great benefits for little effort. You'll know all stacks of
the application work together for the most common scenarios. That's
already something! From there you can always refine a strategy to unit
test critical parts of your application.

Our first test
--------------

Let’s start with the easiest part: our API and the Postgres database.
And let’s run a simple CRUD test. Once we have that framework in place,
we can add more features both to our component and to the test.

Here is our minimal API with a GET/POST to create and list users:

::

   const express = require('express');
   const bodyParser = require('body-parser');
   const cors = require('cors');

   const config = require('../config');

   const db = require('knex')({
     client: 'pg',
     connection: {
       host : config.db.host,
       user : config.db.user,
       password : config.db.password,
     },
   });

   const app = express();

   app.use(bodyParser.urlencoded({ extended: false }));
   app.use(bodyParser.json());
   app.use(cors());

   app.route('/api/users').post(async (req, res, next) => {
     try {
       const { email, firstname } = req.body;
       // ... validate inputs here ...
       const userData = { email, firstname };

       const result = await db('users').returning('id').insert(userData);
       const id = result[0];
       res.status(201).send({ id, ...userData });
     } catch (err) {
       console.log(`Error: Unable to create user: ${err.message}. ${err.stack}`);
       return next(err);
     }
   });

   app.route('/api/users').get((req, res, next) => {
     db('users')
     .select('id', 'email', 'firstname')
     .then(users => res.status(200).send(users))
     .catch(err => {
         console.log(`Unable to fetch users: ${err.message}. ${err.stack}`);
         return next(err);
     });
   });

   try {
     console.log("Starting web server...");

     const port = process.env.PORT || 8000;
     app.listen(port, () => console.log(`Server started on: ${port}`));
   } catch(error) {
     console.error(error.stack);
   }

Here are our tests written with chai. The tests create a new user and
fetch it back. You can see that the tests are not coupled in any way
with the code of our API. The ``SERVER_URL`` variable specifies the
endpoint to test. It can be a local or a remote environment.

::

   const chai = require("chai");
   const chaiHttp = require("chai-http");
   const should = chai.should();

   const SERVER_URL = process.env.APP_URL || "http://localhost:8000";

   chai.use(chaiHttp);

   const TEST_USER = {
     email: "sdof@doe.com",
     firstname: "sdof"
   };

   let createdUserId;

   describe("Users", () => {
     it("should create a new user", done => {
       chai
         .request(SERVER_URL)
         .post("/api/users")
         .send(TEST_USER)
         .end((err, res) => {
           if (err) done(err)
           res.should.have.status(201);
           res.should.be.json;
           res.body.should.be.a("object");
           res.body.should.have.property("id");
           done();
         });
     });

     it("should get the created user", done => {
       chai
         .request(SERVER_URL)
         .get("/api/users")
         .end((err, res) => {
           if (err) done(err)
           res.should.have.status(200);
           res.body.should.be.a("array");

           const user = res.body.pop();
           user.id.should.equal(createdUserId);
           user.email.should.equal(TEST_USER.email);
           user.firstname.should.equal(TEST_USER.firstname);
           done();
         });
     });
   });

Good. Now to test our API let's define a Docker compose environment. A
file called ``docker-compose.yml`` will describe the containers Docker
needs to run.

::

   version: '3.1'

   services:
     db:
       image: postgres
       environment:
         POSTGRES_USER: sdof
         POSTGRES_PASSWORD: sdofmysecretpassword
       expose:
         - 5432

     myapp:
       build: .
       image: myapp
       command: yarn start
       environment:
         APP_DB_HOST: db
         APP_DB_USER: sdof
         APP_DB_PASSWORD: sdofmysecretpassword
       expose:
         - 8000
       depends_on:
         - db

     myapp-tests:
       image: myapp
       command: dockerize
           -wait tcp://db:5432 -wait tcp://myapp:8000 -timeout 10s
           bash -c "node db/init.js && yarn test"
       environment:
         APP_URL: http://myapp:8000
         APP_DB_HOST: db
         APP_DB_USER: sdof
         APP_DB_PASSWORD: sdofmysecretpassword
       depends_on:
         - db
         - myapp

So what do we have here. There are 3 containers:

-  **db** spins up a fresh instance of PostgreSQL. We use the public
   Postgres image from Docker Hub. We set the database username and
   password. We tell Docker to expose the port 5432 the database will
   listen to so other containers can connect
-  **myapp** is the container that will run our API. The ``build``
   command tells Docker to actually build the container image from our
   source. The rest is like the db container: environment variables and
   ports
-  **myapp-tests** is the container that will execute our tests. It will
   use the same image as myapp because the code will already be there so
   there is no need to build it again. The command
   ``node db/init.js && yarn test`` run on the container will initialize
   the database (create tables etc.) and run the tests. We use dockerize
   to wait for all the required servers to be up and running. The
   ``depends_on`` options will ensure that containers start in a certain
   order. It does not ensure that the database inside the db container
   is actually ready to accept connections. Nor that our API server is
   already up.

The definition of the environment is like 20 lines of very easy to
understand code. The only brainy part is the environment definition.
User names, passwords and URLs must be consistent so containers can
actually work together.

One thing to notice is that Docker compose will set the host of the
containers it creates to the name of the container. So the database
won't be available under ``localhost:5432`` but ``db:5432``. The same
way our API will be served under ``myapp:8000``. There is no localhost
of any kind here.

This means that your API must support environment variables when it
comes to environment definition. No hardcoded stuff. But that has
nothing to do with Docker or this article. A configurable application is
point 3 of the `12 factor app manifesto <https://12factor.net/>`__, so
you should be doing it already.

The very last thing we need to tell Docker is how to actually build the
container **myapp**. We use a Dockerfile like below. The content is
specific to your tech stack but the idea is to bundle your API into a
runnable server.

The example below for our Node API installs Dockerize, installs the API
dependencies and copies the code of the API inside the container (the
server is written in raw JS so no need to compile it).

::

   FROM node AS base

   # Dockerize is needed to sync containers startup
   ENV DOCKERIZE_VERSION v0.6.0
   RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
       && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
       && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

   RUN mkdir -p ~/app

   WORKDIR ~/app

   COPY package.json .
   COPY yarn.lock .

   FROM base AS dependencies

   RUN yarn

   FROM dependencies AS runtime

   COPY . .

Typically from the line ``WORKDIR ~/app`` and below you would run
commands that would build your application.

And here is the command we use to run the tests:

::

   docker-compose up --build --abort-on-container-exit

This command will tell Docker compose to spin up the components defined
in our ``docker-compose.yml`` file. The ``--build`` flag will trigger
the build of the myapp container by executing the content of the
``Dockerfile`` above. The ``--abort-on-container-exit`` will tell Docker
compose to shutdown the environment as soon as one container exits.

That works well since the only component meant to exit is the test
container **myapp-tests** after the tests are executed. Cherry on the
cake, the ``docker-compose`` command will exit with the same exit code
as the container that triggered the exit. This means that we can check
if the tests succeeded or not from the command line. This is very useful
for automated builds in a CI environment.

Isn't that the perfect test setup?

The full example is `here on
GitHub <https://github.com/fire-ci/tuto-api-e2e-testing>`__. You can
clone the repository and run the docker compose command:

::

   docker-compose up --build --abort-on-container-exit

Of course you need Docker installed. Docker has the troublesome tendency
of forcing you to sign up for an account just to download the thing. But
you actually don't have to. Go to the release notes (`link for
Windows <https://docs.docker.com/docker-for-windows/release-notes/>`__
and `link for
Mac <https://docs.docker.com/docker-for-mac/release-notes/>`__) and
download not the latest version but the one right before. This is a
direct download link.

The very first run of the tests will be longer than usual. This is
because Docker will have to download the base images for your containers
and cache a few things. The next runs will be much faster.

Logs from the run will look as below. You can see that Docker is cool
enough to put logs from all the components on the same timeline. This is
very handy when looking for errors.

::

   Creating tuto-api-e2e-testing_db_1    ... done
   Creating tuto-api-e2e-testing_redis_1 ... done
   Creating tuto-api-e2e-testing_myapp_1 ... done
   Creating tuto-api-e2e-testing_myapp-tests_1 ... done
   Attaching to tuto-api-e2e-testing_redis_1, tuto-api-e2e-testing_db_1, tuto-api-e2e-testing_myapp_1, tuto-api-e2e-testing_myapp-tests_1
   db_1           | The files belonging to this database system will be owned by user "postgres".
   redis_1        | 1:M 09 Nov 2019 21:57:22.161 * Running mode=standalone, port=6379.
   myapp_1        | yarn run v1.19.0
   redis_1        | 1:M 09 Nov 2019 21:57:22.162 # WARNING: The TCP backlog setting of 511 cannot be enforced because /proc/sys/net/core/somaxconn is set to the lower value of 128.
   redis_1        | 1:M 09 Nov 2019 21:57:22.162 # Server initialized
   db_1           | This user must also own the server process.
   db_1           |
   db_1           | The database cluster will be initialized with locale "en_US.utf8".
   db_1           | The default database encoding has accordingly been set to "UTF8".
   db_1           | The default text search configuration will be set to "english".
   db_1           |
   db_1           | Data page checksums are disabled.
   db_1           |
   db_1           | fixing permissions on existing directory /var/lib/postgresql/data ... ok
   db_1           | creating subdirectories ... ok
   db_1           | selecting dynamic shared memory implementation ... posix
   myapp-tests_1  | 2019/11/09 21:57:25 Waiting for: tcp://db:5432
   myapp-tests_1  | 2019/11/09 21:57:25 Waiting for: tcp://redis:6379
   myapp-tests_1  | 2019/11/09 21:57:25 Waiting for: tcp://myapp:8000
   myapp_1        | $ node server.js
   redis_1        | 1:M 09 Nov 2019 21:57:22.163 # WARNING you have Transparent Huge Pages (THP) support enabled in your kernel. This will create latency and memory usage issues with Redis. To fix this issue run the command 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' as root, and add it to your /etc/rc.local in order to retain the setting after a reboot. Redis must be restarted after THP is disabled.
   db_1           | selecting default max_connections ... 100
   myapp_1        | Starting web server...
   myapp-tests_1  | 2019/11/09 21:57:25 Connected to tcp://myapp:8000
   myapp-tests_1  | 2019/11/09 21:57:25 Connected to tcp://db:5432
   redis_1        | 1:M 09 Nov 2019 21:57:22.164 * Ready to accept connections
   myapp-tests_1  | 2019/11/09 21:57:25 Connected to tcp://redis:6379
   myapp_1        | Server started on: 8000
   db_1           | selecting default shared_buffers ... 128MB
   db_1           | selecting default time zone ... Etc/UTC
   db_1           | creating configuration files ... ok
   db_1           | running bootstrap script ... ok
   db_1           | performing post-bootstrap initialization ... ok
   db_1           | syncing data to disk ... ok
   db_1           |
   db_1           |
   db_1           | Success. You can now start the database server using:
   db_1           |
   db_1           |     pg_ctl -D /var/lib/postgresql/data -l logfile start
   db_1           |
   db_1           | initdb: warning: enabling "trust" authentication for local connections
   db_1           | You can change this by editing pg_hba.conf or using the option -A, or
   db_1           | --auth-local and --auth-host, the next time you run initdb.
   db_1           | waiting for server to start....2019-11-09 21:57:24.328 UTC [41] LOG:  starting PostgreSQL 12.0 (Debian 12.0-2.pgdg100+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 8.3.0-6) 8.3.0, 64-bit
   db_1           | 2019-11-09 21:57:24.346 UTC [41] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
   db_1           | 2019-11-09 21:57:24.373 UTC [42] LOG:  database system was shut down at 2019-11-09 21:57:23 UTC
   db_1           | 2019-11-09 21:57:24.383 UTC [41] LOG:  database system is ready to accept connections
   db_1           |  done
   db_1           | server started
   db_1           | CREATE DATABASE
   db_1           |
   db_1           |
   db_1           | /usr/local/bin/docker-entrypoint.sh: ignoring /docker-entrypoint-initdb.d/*
   db_1           |
   db_1           | waiting for server to shut down....2019-11-09 21:57:24.907 UTC [41] LOG:  received fast shutdown request
   db_1           | 2019-11-09 21:57:24.909 UTC [41] LOG:  aborting any active transactions
   db_1           | 2019-11-09 21:57:24.914 UTC [41] LOG:  background worker "logical replication launcher" (PID 48) exited with exit code 1
   db_1           | 2019-11-09 21:57:24.914 UTC [43] LOG:  shutting down
   db_1           | 2019-11-09 21:57:24.930 UTC [41] LOG:  database system is shut down
   db_1           |  done
   db_1           | server stopped
   db_1           |
   db_1           | PostgreSQL init process complete; ready for start up.
   db_1           |
   db_1           | 2019-11-09 21:57:25.038 UTC [1] LOG:  starting PostgreSQL 12.0 (Debian 12.0-2.pgdg100+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 8.3.0-6) 8.3.0, 64-bit
   db_1           | 2019-11-09 21:57:25.039 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
   db_1           | 2019-11-09 21:57:25.039 UTC [1] LOG:  listening on IPv6 address "::", port 5432
   db_1           | 2019-11-09 21:57:25.052 UTC [1] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
   db_1           | 2019-11-09 21:57:25.071 UTC [59] LOG:  database system was shut down at 2019-11-09 21:57:24 UTC
   db_1           | 2019-11-09 21:57:25.077 UTC [1] LOG:  database system is ready to accept connections
   myapp-tests_1  | Creating tables ...
   myapp-tests_1  | Creating table 'users'
   myapp-tests_1  | Tables created succesfully
   myapp-tests_1  | yarn run v1.19.0
   myapp-tests_1  | $ mocha --timeout 10000 --bail
   myapp-tests_1  |
   myapp-tests_1  |
   myapp-tests_1  |   Users
   myapp-tests_1  | Mock server started on port: 8002
   myapp-tests_1  |     ✓ should create a new user (151ms)
   myapp-tests_1  |     ✓ should get the created user
   myapp-tests_1  |     ✓ should not create user if mail is spammy
   myapp-tests_1  |     ✓ should not create user if spammy mail API is down
   myapp-tests_1  |
   myapp-tests_1  |
   myapp-tests_1  |   4 passing (234ms)
   myapp-tests_1  |
   myapp-tests_1  | Done in 0.88s.
   myapp-tests_1  | 2019/11/09 21:57:26 Command finished successfully.
   tuto-api-e2e-testing_myapp-tests_1 exited with code 0

We can see that **db** is the container that initializes the longest.
Makes sense. Once it's done the tests start. The total runtime on my
laptop is 16 seconds. Compared to the 880ms used to actually execute the
tests, it is a lot. In practice, tests that run under 1 minute are gold
as it is almost immediate feedback. The 15'ish seconds overhead are a
buy in time that will be constant as you add more tests. You could add
hundreds of tests and still keep execution time under 1 minute.

Voilà! We have our test framework up and running. In a real world
project the next steps would be to enhance functional coverage of your
API with more tests. Let's consider CRUD operations covered. It's time
to add more elements to our test environment.

Adding a Redis cluster
----------------------

Let's add another element to our API environment to understand what it
takes. Spoiler alert: it's not much.

Let us imagine that our API keeps user sessions in a Redis cluster. If
you wonder why we would do that, imagine 100 instances of your API in
production. Users hit one or another server based on round robin load
balancing. Every request needs to be authenticated.

This requires user profile data to check for privileges and other
application specific business logic. One way to go is to make a round
trip to the database to fetch the data every time you need it, but that
is not very efficient. Using an in memory database cluster makes the
data available across all servers for the cost of a local variable read.

This is how you enhance your Docker compose test environment with an
additional service. Let’s add a Redis cluster from the official Docker
image (I've only kept the new parts of the file):

::

   services:
     db:
       ...

     redis:
       image: "redis:alpine"
       expose:
         - 6379

     myapp:
       environment:
         APP_REDIS_HOST: redis
         APP_REDIS_PORT: 6379
       ...
     myapp-tests:
       command: dockerize ... -wait tcp://redis:6379 ...
       environment:
         APP_REDIS_HOST: redis
         APP_REDIS_PORT: 6379
         ...
       ...

You can see it's not much. We added a new container called **redis**. It
uses the official minimal redis image called ``redis:alpine``. We added
Redis host and port configuration to our API container. And we've made
tests wait for it as well as the other containers before executing the
tests.

Let’s modify our application to actually use the Redis cluster:

::

   const redis = require('redis').createClient({
     host: config.redis.host,
     port: config.redis.port,
   })

   ...

   app.route('/api/users').post(async (req, res, next) => {
     try {
       const { email, firstname } = req.body;
       // ... validate inputs here ...
       const userData = { email, firstname };
       const result = await db('users').returning('id').insert(userData);
       const id = result[0];

       // Once the user is created store the data in the Redis cluster
       await redis.set(id, JSON.stringify(userData));

       res.status(201).send({ id, ...userData });
     } catch (err) {
       console.log(`Error: Unable to create user: ${err.message}. ${err.stack}`);
       return next(err);
     }
   });

Let's now change our tests to check that the Redis cluster is populated
with the right data. That's why the **myapp-tests** container also gets
the Redis host and port configuration in ``docker-compose.yml``.

::

   it("should create a new user", done => {
     chai
       .request(SERVER_URL)
       .post("/api/users")
       .send(TEST_USER)
       .end((err, res) => {
         if (err) throw err;
         res.should.have.status(201);
         res.should.be.json;
         res.body.should.be.a("object");
         res.body.should.have.property("id");
         res.body.should.have.property("email");
         res.body.should.have.property("firstname");
         res.body.id.should.not.be.null;
         res.body.email.should.equal(TEST_USER.email);
         res.body.firstname.should.equal(TEST_USER.firstname);
         createdUserId = res.body.id;

         redis.get(createdUserId, (err, cacheData) => {
           if (err) throw err;
           cacheData = JSON.parse(cacheData);
           cacheData.should.have.property("email");
           cacheData.should.have.property("firstname");
           cacheData.email.should.equal(TEST_USER.email);
           cacheData.firstname.should.equal(TEST_USER.firstname);
           done();
         });
       });
   });

See how easy this was. You can build a complex environment for your
tests like you assemble Lego bricks.

We can see another benefit of this kind of containerized full
environment testing. The tests can actually look into the environment's
components. Our tests can not only check that our API returns the proper
response codes and data. We can also check that data in the Redis
cluster have the proper values. We could also check the database
content.

Adding API mocks
----------------

A common element for API components is to call other API components.

Let's say our API needs to check for spammy user emails when creating a
user. The check is done using a third party service:

::

   const validateUserEmail = async (email) => {
     const res = await fetch(`${config.app.externalUrl}/validate?email=${email}`);
     if(res.status !== 200) return false;
     const json = await res.json();
     return json.result === 'valid';
   }

   app.route('/api/users').post(async (req, res, next) => {
     try {
       const { email, firstname } = req.body;
       // ... validate inputs here ...
       const userData = { email, firstname };

       // We don't just create any user. Spammy emails should be rejected
       const isValidUser = await validateUserEmail(email);
       if(!isValidUser) {
         return res.sendStatus(403);
       }

       const result = await db('users').returning('id').insert(userData);
       const id = result[0];
       await redis.set(id, JSON.stringify(userData));
       res.status(201).send({ id, ...userData });
     } catch (err) {
       console.log(`Error: Unable to create user: ${err.message}. ${err.stack}`);
       return next(err);
     }
   });

Now we have a problem for testing anything. We can't create any users if
the API to detect spammy emails is not available. Modifying our API to
bypass this step in test mode is a dangerous cluttering of the code.

Even if we could use the real third party service, we don't want to do
that. As a general rule our tests should not depend on external
infrastructure. First of all, because you will probably run your tests a
lot as part of your CI process. It’s not that cool to consume another
production API for this purpose. Second of all the API might be
temporarily down, failing your tests for the wrong reasons.

The right solution is to mock the external APIs in our tests.

No need for any fancy framework. We'll build a generic mock in vanilla
JS in ~20 lines of code. This will give us the opportunity to control
what the API will return to our component. It allows to test error
scenarios.

Now let’s enhance our tests.

::


   const express = require("express");

   ...

   const MOCK_SERVER_PORT = process.env.MOCK_SERVER_PORT || 8002;

   // Some object to encapsulate attributes of our mock server
   // The mock stores all requests it receives in the `requests` property.
   const mock = {
     app: express(),
     server: null,
     requests: [],
     status: 404,
     responseBody: {}
   };

   // Define which response code and content the mock will be sending
   const setupMock = (status, body) => {
     mock.status = status;
     mock.responseBody = body;
   };

   // Start the mock server
   const initMock = async () => {
     mock.app.use(bodyParser.urlencoded({ extended: false }));
     mock.app.use(bodyParser.json());
     mock.app.use(cors());
     mock.app.get("*", (req, res) => {
       mock.requests.push(req);
       res.status(mock.status).send(mock.responseBody);
     });

     mock.server = await mock.app.listen(MOCK_SERVER_PORT);
     console.log(`Mock server started on port: ${MOCK_SERVER_PORT}`);
   };

   // Destroy the mock server
   const teardownMock = () => {
     if (mock.server) {
       mock.server.close();
       delete mock.server;
     }
   };

   describe("Users", () => {
     // Our mock is started before any test starts ...
     before(async () => await initMock());

     // ... killed after all the tests are executed ...
     after(() => {
       redis.quit();
       teardownMock();
     });

     // ... and we reset the recorded requests between each test
     beforeEach(() => (mock.requests = []));

     it("should create a new user", done => {
       // The mock will tell us the email is valid in this test
       setupMock(200, { result: "valid" });

       chai
         .request(SERVER_URL)
         .post("/api/users")
         .send(TEST_USER)
         .end((err, res) => {
           // ... check response and redis as before
           createdUserId = res.body.id;

           // Verify that the API called the mocked service with the right parameters
           mock.requests.length.should.equal(1);
           mock.requests[0].path.should.equal("/api/validate");
           mock.requests[0].query.should.have.property("email");
           mock.requests[0].query.email.should.equal(TEST_USER.email);
           done();
         });
     });
   });

The tests now check that the external API has been hit with the proper
data during the call to our API.

We can also add other tests checking how our API behaves based on the
external API response codes:

::

   describe("Users", () => {
     it("should not create user if mail is spammy", done => {
       // The mock will tell us the email is NOT valid in this test ...
       setupMock(200, { result: "invalid" });

       chai
         .request(SERVER_URL)
         .post("/api/users")
         .send(TEST_USER)
         .end((err, res) => {
           // ... so the API should fail to create the user
           // We could test that the DB and Redis are empty here
           res.should.have.status(403);
           done();
         });
     });

     it("should not create user if spammy mail API is down", done => {
       // The mock will tell us the email checking service
       //  is down for this test ...
       setupMock(500, {});

       chai
         .request(SERVER_URL)
         .post("/api/users")
         .send(TEST_USER)
         .end((err, res) => {
           // ... in that case also a user should not be created
           res.should.have.status(403);
           done();
         });
     });
   });

How you handle errors from third party APIs in your application is of
course up to you. But you get the point.

To run these tests we need to tell the container **myapp** what is the
base URL of the third party service:

::

     myapp:
       environment:
         APP_EXTERNAL_URL: http://myapp-tests:8002/api
       ...

     myapp-tests:
       environment:
         MOCK_SERVER_PORT: 8002
       ...

Conclusion and a few other thoughts
-----------------------------------

Hopefully this article gave you a taste of what Docker compose can do
for you when it comes to API testing. The full example is `here on
GitHub <https://github.com/fire-ci/tuto-api-e2e-testing>`__.

Using Docker compose makes tests run fast in an environment close to
production. It requires no adaptations to your component code. The only
requirement is to support environment variables driven configuration.

The component logic in this example is very simple but the principles
apply to any API. Your tests will just be longer or more complex. They
also apply to any tech stack that can be put inside a container (that's
all of them). And once you are there you are one step away from
deploying your containers to production if need be.

If you have no tests right now this is how I recommend you should start:
end to end testing with Docker compose. It is so simple you could have
your first test running in a few hours. Feel free to `reach out to
me <https://twitter.com/jpdelimat>`__ if you have questions or need
advice. I'd be happy to help.

I hope you enjoyed this article and will start testing your APIs with
Docker Compose. Once you have the tests ready you can run them out of
the box on our continuous integration platform `Fire
CI <https://fire.ci>`__.

.. _one-last-idea-to-succeed-with-automated-testing-:

One last idea to succeed with automated testing.
------------------------------------------------

When it comes to maintaining large test suites, the most important
feature is that tests are easy to read and understand. This is key to
motivate your team to keep the tests up to date. Complex tests
frameworks are unlikely to be properly used in the long run.

Regardless of the stack for your API, you might want to consider using
chai/mocha to write tests for it. It might seem unusual to have
different stacks for runtime code and test code, but if it gets the job
done ... As you can see from the examples in this article, testing a
REST API with chai/mocha is as simple as it gets. The learning curve is
close to zero.

So if you have no tests at all and have a REST API to test written in
Java, Python, RoR, .NET or whatever other stack, you might consider
giving chai/mocha a try.

If you wonder how to get start with continuous integration at all, I
have written a broader guide about it. Here it is: `How to get started
with Continuous
Integration <https://fire.ci/blog/how-to-get-started-with-continuous-integration/>`__

Originally published on the `Fire CI Blog <https://fire.ci/blog/>`__.
