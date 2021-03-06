library(keras)
library(data.table)
library(ggplot2)

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))


# read in data
spam_datatable <- data.table::fread("spam.data")


# split data into usable elements
x <- spam_datatable[, -58]
x_scale <- scale(x)

y <- spam_datatable[, 58]

is_train <- vector(mode = "logical", length = nrow(x))
is_train <- sample(c(TRUE, FALSE), nrow(x), replace = TRUE, prob = c(0.8, 0.2))



# training models
model_dropout <- c(0.03,0.06,0.09,0.12,0.15,0.18, 0.21, 0.24, 0.27, 0.30, 0.33, 0.36, 0.39, 0.42, 0.45)
num_models <- length(model_dropout)
max_epochs <- 400

models <- list()
metric_list <- list()
for( model_num in 1:num_models){
  
  model <- keras_model_sequential() %>%
    layer_dense( units = 20, activation = "sigmoid", input_shape = c(ncol(x))) %>%
    layer_dropout(model_dropout[model_num]) %>%
    layer_dense(1, activation = "sigmoid")
  
  model %>%
    compile(
      loss= "binary_crossentropy",
      optimizer = "sgd",
      metrics = "accuracy"
    )
  
  history <- model %>%
    fit(
      x = x_scale[is_train,],
      y = as.matrix(y[is_train]),
      epochs = max_epochs,
      validation_split = 0.5,
      verbose = 2,
      view_metrics = FALSE
    )
  
  # modify data
  metric <- do.call(data.table::data.table, history$metrics)
  metric[, epoch := 1:.N]
  metric[, model_num := model_num]
  
  models[[model_num]] <- model
  metric_list[[model_num]] <- metric
}

metrics <- do.call(rbind, metric_list)

# val loss and dropout by model num
val_loss_by_dropout <- metrics[, .(
  val_loss = val_loss[max_epochs],
  dropout_rate = model_dropout[model_num],
  train_loss = loss[max_epochs] 
), by = model_num]


# plot val loss for each model
ggplot()+
  geom_line(aes(
    x=model_dropout, y=val_loss),
    data=val_loss_by_dropout)+
  geom_line(aes(
    x=model_dropout, y=train_loss),
    data=val_loss_by_dropout)+
  geom_point(aes(
    x=dropout_rate[which.min(val_loss)], y=min(val_loss)), data = val_loss_by_dropout)


# find dropout rate with best val_loss
best_dropout_value <- val_loss_by_dropout$dropout_rate[which.min(val_loss_by_dropout$val_loss)]
best_model <- match(best_dropout_value, model_dropout)
best_model <- models[[best_model]]

# retrain best dropout rate with 100% of train data
best_model %>%
  fit(
    x = x_scale[is_train,],
    y = as.matrix(y[is_train]),
    epochs = max_epochs,
    validation_split = 0,
    verbose = 2,
    view_metrics = FALSE
  )

# compute accuracy on test set
best_model %>%
  evaluate( x_scale[!is_train,], as.matrix(y[!is_train]))

# accuracy of baseline prediction
y_tab <- table(y[is_train])
y_baseline <- as.integer(names(which.max(y_tab)))
mean(y[!is_train] == y_baseline)

