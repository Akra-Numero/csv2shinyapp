#!/usr/bin/env bash

## csv2shinyapp.sh
## Create shiny app files from data in CSV format
## Bijoy Joseph
## 2017.11.09
## Usage: $0  CSV_FILE
#+  e.g.: $0 /home/user/csvdata.csv
#+ This creates the folder /home/user/csvdata and adds a server.R and ui.R files within
#+ Copy these to the shiny server path, or run the app using "Rscript $SHINY_APP/run_app.R"

## Check for ARGV 
  if test $# -ne 1; then
    echo "Usage: $0  CSV_FILE"
    echo -e " e.g.: $0 /home/user/data.csv\n"
    exit 1
  fi

  [ -s "$1" ] || {
    echo "*** ERROR: CSV data file ($1) does not exist! ..." 
    exit 1
  }

## Get the APP name and file path from the filename
  SHINY_APP=$(basename "$1" | rev | cut -f2 -d '.' | rev | sed -e 's/ //g')
  APP_PATH=$(dirname "$1")
  mkdir $APP_PATH/$SHINY_APP/

  ## signal processing 
  trap "rm -rf ${SHINY_APP}; exit" SIGHUP SIGINT SIGTERM

  echo -e "\nCreating shiny app files for: $1\n"

## Determine the delimiter (and number of variables)
  DELIM=$(head -n1 "$1" | sed -e 's/[-a-zA-Z0-9 _%=+\*\$\#\@\!)({}\?\&\."]//g;s%[\[/\]%%g' | sed -e 's/\]//g' | cut -b1)
  NUMVARS=$(head -n1 "$1" | sed -e 's/[- _%=+\*\$\#\@\!)({}\?\&]/_/g;s%[\[/\]%%g' \
     | sed -e 's/\]//g' | sed -e "s/$DELIM/ /g" | wc -w)

  echo "  -> Delimiter= $DELIM, Number of variables=$NUMVARS"

## Read in the data and create an R data file
  if [ $DELIM == ',' ]; then
    R -q -e "$SHINY_APP=read.csv(\"$1\",sep=',', header=TRUE); save($SHINY_APP,file=\"$APP_PATH/$SHINY_APP/${SHINY_APP}.Rda\")"
  else
    R -q -e "$SHINY_APP=read.csv2(\"$1\",sep=\"$DELIM\", header=TRUE); save($SHINY_APP,file=\"$APP_PATH/$SHINY_APP/${SHINY_APP}.Rda\")"
  fi

## Write out ui.R
cat >> $APP_PATH/$SHINY_APP/ui.R << __WRITE_UI__
library(shiny)
shinyUI(fluidPage(
  titlePanel("Data summary: $SHINY_APP"),
  
  sidebarLayout(
    sidebarPanel(
      helpText("Select the dataset (followed by variable)"),
      selectInput("dataset", label="Dataset", choices = c("$SHINY_APP"), selected = "$SHINY_APP"),
      selectInput("var2show", label = "Variable to summarise", choices = character(0), selected=NULL),
      radioButtons("inXtab", "Cross-tabulate?",
                     c("No" = 0,
                       "Yes" = 1), selected = 0),

      conditionalPanel(condition = "input.inXtab == 1",
         selectizeInput("var2xtab", label = "Variable to cross tabulate with:", choices = "varchoices",selected = character(0))
       ),
      br(),
      br()),

    mainPanel(
      tabsetPanel(
        tabPanel("Table",
            helpText("Frequency table"),
            tableOutput("summary")
        ),
        tabPanel("Graph",
            helpText("Graph of counts of the variable"),
            plotOutput("plot1",width="100%")
        ),
        tabPanel("Summary",
            helpText("Some features of the variable"),
            verbatimTextOutput("datarows10")
        ),
        tabPanel("Misc.",
            helpText("Names of variables in the dataset"),
            verbatimTextOutput("names"),
            helpText("Input vars used"),
            verbatimTextOutput("usedvars")
        )
      )
    )
  )
))
__WRITE_UI__

## Write out server.R
cat >> $APP_PATH/$SHINY_APP/server.R << __WRITE_SERVER__
# server.R
# Install packages 'shiny' and 'rmarkdown'

library(shiny)
library(plyr)           # if using plyr:count()

Sys.setlocale(category="LC_COLLATE",locale="fi_FI.UTF-8")
load("$SHINY_APP.Rda")

shinyServer(function(input, output, session) {
  datasetInput <- reactive({
    switch(input\$dataset,
           "$SHINY_APP" = $SHINY_APP
    )
  })

  sdataset <- reactive({ datasetInput() })
  varchoices <- reactive({ unlist(names(datasetInput())) })

  observe({
    updateSelectizeInput(session, "var2show",
       label = "Variable to summarise",
       choices = varchoices(),
       selected = character(0)
    )

     updateSelectizeInput(session, "var2xtab",
        label = "Variable to cross tabulate with",
        choices = varchoices(),
        selected = character(0),
        server = FALSE
     )
  })

  userdata <- reactive({
    indataset <- eval(parse(text=input\$dataset))
    if(! input\$inXtab == ' ') {
      if(input\$inXtab == '0') {
        table(indataset[[input\$var2show]], dnn=c(input\$var2show), deparse.level = 2)
      } else {
        ftable(table(indataset[[input\$var2xtab]],indataset[[input\$var2show]], dnn=c(input\$var2xtab,input\$var2show), deparse.level = 2))
      }
    }
  })
  
  output\$summary <- renderTable({
    userdata()
  })

  output\$plot1 <- renderPlot({
    if(input\$var2show != '') {
      x = as.data.frame(table(sdataset()[[input\$var2show]]))
      plot(x=x\$Var1,y=x\$Freq)
    }
  })

  output\$names <- renderPrint({
    print(cat(unlist(names(sdataset()))))
  })

  output\$datarows10 <- renderPrint({
    print("------------ 10 Rows of data ----------------")
    print(head(sdataset()[[input\$var2show]],10))
    print("------------ Summary of data ----------------")
    print(summary(sdataset()[[input\$var2show]])) 
    print("---- Frequency counts with plyr::count() ----")
    print(count(sdataset()[[input\$var2show]]))
  })

  output\$usedvars <- renderPrint({
    print(paste("dataset = ", input\$dataset))
    print(paste("var2show = ", input\$var2show))
    print(paste("var2xtab = ", input\$var2xtab))
    print(paste("inXtab update = ", input\$inXtab))
  })
})
__WRITE_SERVER__

## Write out run_app.R 
  echo -e "  source(\"server.R\")\n  source(\"ui.R\")\n  runApp()" > $APP_PATH/$SHINY_APP/run_app.R
