# Spring Petclinic demo

## Start demo

    ./run_petclinic_demo.sh

This will create a new `kind` cluster, install GlooE and petclinic application, and
open up web browser pages to GlooE console and PetClinic home page. It also installs
petstore (OpenAPI service) and AWS upstreams.

## Script

1. Walk viewer through Spring PetClinic application explaining that its an example
of a monolithic application.
    * The `Find Owners` page lets you search by last name for pet owners. Click on
     `Find Owner` button and the page displays a table which is a query against
     a cluster local MySQL database.
    * The `Veterinarians` page shows a **two** column table of vets. Highlight that
      its **two** columns as that will change in a later step of this demo script.
      This table is also being pulled from cluster local MySql.
    * The `Contact` page has not been implemented (yet).
1. Explain that one of the developers created a new version of the `Veterinarians`
page in Golang. Wouldn't it be cool if you could gloo in that new implementation
without touching the Java monolithic application? GlooE lets you do that.
1. In the GlooE web console, walk the viewer through the main Catalog page. Highlight
that GlooE is autodiscovering: all Kubernetes Services; all REST (OpenAPI/Swagger)
functions; and AWS Lambda functions.
1. Click into the `default` virtual service.
1. Explain that Gloo uses a `VirtualService` Custom Resource to control function
level routing.
1. Say you're going to create a new route to gloo in the new Vets page.
    * Click `Add Route`
    * In the `New Route` popup, enter in the Path field: `/vets`
    * Point out that we're doing path prefix matching and that exact and regex
      are also options
    * In the Upstream Name dropdown select `default-petclinic-vets-8080`
    * Click `Submit`
    * Click-drag new `/vets` route up on top of `/` route so it gets matched first
    * Go back to Spring PetClinic Veterianarians page and show the new **three**
      column table (city field).
1. Explain that what differentiates GlooE is that it operates at a function level
which allows us to route to individual OpenAPI/Swagger and AWS Lambda functions.
    * Go back to the `default` virtual service editor page in GlooE.
    * Click `Add Route`
    * In the `New Route` popup, enter in the Path field: `/contact`
    * In the Upstream Name dropdown select `aws`
    * In the Logical Name dropdown select `contact-form:3`
    * In Response Transformation dropdown select: `Enabled` explaining that AWS
      Lambda response is a JSON object, and GlooE supports response (and request)
      transformations. We're going to enable that in this case so we can display
      the returned HTML page.
    * Click `Submit`
    * Click-drag new `/contact` route up on top of Routes list so it gets matched first
    * Go back to the Spring PetClinic Contact page and show the new form

## Reset

Delete `/vets` and `/contact` routes in default virtual service.
