# csv2shinyapp

Bash script to create a shiny app from data in a CSV file format.
The script creates a folder of the same name as the CSV file and adds a run_app.R, server.R and ui.R files within.
Copy these to a shiny server location, or run the app using "Rscript /Path/to/app/run_app.R".

The shiny app is quite simple, but it is possible to add more datasets to server.R, within switch(input$dataset, ...).
