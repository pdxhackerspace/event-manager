# A blob whose file is already gone raises ActiveStorage::FileNotFoundError.
# Sidekiq would otherwise retry that for about three weeks. Try a few times
# in case the upload has not landed, then drop the job.
Rails.application.config.after_initialize do
  ActiveStorage::AnalyzeJob.retry_on(
    ActiveStorage::FileNotFoundError,
    attempts: 5,
    wait: :polynomially_longer
  ) do |job, error|
    blob_id = job.arguments.first&.id
    Rails.logger.warn("ActiveStorage::AnalyzeJob stopped retrying blob #{blob_id}: #{error.message}")
  end
end
