require_relative "test_helper"

class TrainTest < Minitest::Test
  def test_train_regression
    x_test = boston_test.data
    y_test = boston_test.label

    params = {objective: "regression"}
    model = LightGBM.train(params, boston_train, valid_sets: [boston_train, boston_test], verbose_eval: false)
    y_pred = model.predict(x_test)
    assert_operator rsme(y_test, y_pred), :<=, 6

    model.save_model("/tmp/model.txt")
    model = LightGBM::Booster.new(model_file: "/tmp/model.txt")
    y_pred = model.predict(x_test)
    assert_operator rsme(y_test, y_pred), :<=, 6
  end

  def test_train_classification_binary
    model = LightGBM.train(binary_params, iris_train, valid_sets: [iris_train, iris_test], verbose_eval: false)
    y_pred = model.predict([6.3, 2.7, 4.9, 1.8])
    assert_in_delta 0.99998366, y_pred

    y_pred = model.predict(iris_test.data)
    assert_equal 50, y_pred.size

    model.save_model("/tmp/model.txt")
    model = LightGBM::Booster.new(model_file: "/tmp/model.txt")
    y_pred2 = model.predict(iris_test.data)
    assert_equal y_pred, y_pred2
  end

  def test_train_classification_multiclass
    model = LightGBM.train(multiclass_params, iris_train, valid_sets: [iris_train, iris_test], verbose_eval: false)
    y_pred = model.predict([6.3, 2.7, 4.9, 1.8])
    assert_in_delta 3.91608299e-04, y_pred[0]
    assert_in_delta 3.81933551e-01, y_pred[1]
    assert_in_delta 6.17674841e-01, y_pred[2]

    y_pred = model.predict(iris_test.data)
    # ensure reshaped
    assert_equal 50, y_pred.size
    assert_equal 3, y_pred.first.size

    model.save_model("/tmp/model.txt")
    model = LightGBM::Booster.new(model_file: "/tmp/model.txt")
    y_pred2 = model.predict(iris_test.data)
    assert_equal y_pred, y_pred2
  end

  def test_early_stopping_early
    model = nil
    stdout, _ = capture_io do
      model = LightGBM.train(regression_params, boston_train, valid_sets: [boston_train, boston_test], early_stopping_rounds: 5)
    end
    assert_equal 55, model.best_iteration
    assert_includes stdout, "Early stopping, best iteration is:\n[55]\ttraining's l2: 2.18872\tvalid_1's l2: 35.6151"
  end

  def test_early_stopping_not_early
    model = nil
    stdout, _ = capture_io do
      model = LightGBM.train(regression_params, boston_train, valid_sets: [boston_train, boston_test], early_stopping_rounds: 500)
    end
    assert_equal 71, model.best_iteration
    assert_includes stdout, "Best iteration is: [71]\ttraining's l2: 1.69138\tvalid_1's l2: 35.2563"
  end

  def test_verbose_eval_false
    stdout, _ = capture_io do
      LightGBM.train(regression_params, boston_train, valid_sets: [boston_train, boston_test], early_stopping_rounds: 5, verbose_eval: false)
    end
    assert_empty stdout
  end

  def test_bad_params
    params = {objective: "regression verbosity=1"}
    assert_raises ArgumentError do
      LightGBM.train(params, boston_train)
    end
  end

  def test_cv_regression
    eval_hist = LightGBM.cv(regression_params, boston, shuffle: false)
    assert_in_delta 82.33637413467392, eval_hist["l2-mean"].first
    assert_in_delta 22.55870116923647, eval_hist["l2-mean"].last
    assert_in_delta 35.018415375374886, eval_hist["l2-stdv"].first
    assert_in_delta 11.605523321472438, eval_hist["l2-stdv"].last
  end

  def test_cv_classification_binary
    # need to set stratified=False in Python
    eval_hist = LightGBM.cv(binary_params, iris, shuffle: false)
    assert_in_delta 0.5523814945253853, eval_hist["binary_logloss-mean"].first
    assert_in_delta 0.0702413393927758, eval_hist["binary_logloss-mean"].last
    assert_in_delta 0.04849276982520402, eval_hist["binary_logloss-stdv"].first
    assert_in_delta 0.14004060158158324, eval_hist["binary_logloss-stdv"].last
  end

  def test_cv_classification_multiclass
    # need to set stratified=False in Python
    eval_hist = LightGBM.cv(multiclass_params, iris, shuffle: false)
    assert_in_delta 0.9968127754694314, eval_hist["multi_logloss-mean"].first
    assert_in_delta 0.23619145913652034, eval_hist["multi_logloss-mean"].last
    assert_in_delta 0.017988535469258864, eval_hist["multi_logloss-stdv"].first
    assert_in_delta 0.19730616941199997, eval_hist["multi_logloss-stdv"].last
  end

  def test_cv_early_stopping_early
    eval_hist = nil
    stdout, _ = capture_io do
      eval_hist = LightGBM.cv(regression_params, boston, shuffle: false, verbose_eval: true, early_stopping_rounds: 5)
    end
    assert_equal 49, eval_hist["l2-mean"].size
    assert_includes stdout, "[49]\tcv_agg's l2: 21.6348 + 12.0872"
    refute_includes stdout, "[50]"
  end

  def test_cv_early_stopping_not_early
    eval_hist = nil
    stdout, _ = capture_io do
      eval_hist = LightGBM.cv(regression_params, boston, shuffle: false, verbose_eval: true, early_stopping_rounds: 500)
    end
    assert_equal 100, eval_hist["l2-mean"].size
    assert_includes stdout, "[100]\tcv_agg's l2: 22.5587 + 11.6055"
  end

  def test_train_categorical_feature
    train_set = LightGBM::Dataset.new(boston_train.data, label: boston_train.label, categorical_feature: [5])
    model = LightGBM.train(regression_params, train_set)
    assert_in_delta 22.33155937, model.predict(boston_test.data[0])
  end

  def test_train_multiple_metrics
    params = regression_params.dup
    params[:metric] = ["l1", "l2", "rmse"]
    LightGBM.train(params, boston_train, valid_sets: [boston_train, boston_test], early_stopping_rounds: 5)
  end

  private

  def regression_params
    {objective: "regression", metric: "mse"}
  end

  def binary_params
    {objective: "binary"}
  end

  def multiclass_params
    {objective: "multiclass", num_class: 3}
  end

  def rsme(y_true, y_pred)
    Math.sqrt(y_true.zip(y_pred).map { |a, b| (a - b)**2 }.sum / y_true.size.to_f)
  end
end
