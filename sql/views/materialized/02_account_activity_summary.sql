DROP MATERIALIZED VIEW IF EXISTS public.account_activity_summary;

CREATE MATERIALIZED VIEW public.account_activity_summary AS
WITH account_mentions AS (
  SELECT 
    t.account_id,
    um.mentioned_user_id,
    COUNT(*) as mention_count
  FROM public.tweets t
  JOIN public.user_mentions um ON t.tweet_id = um.tweet_id
  GROUP BY t.account_id, um.mentioned_user_id
),
ranked_tweets AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (
      PARTITION BY account_id 
      ORDER BY (retweet_count + favorite_count) DESC
    ) as engagement_rank
  FROM public.tweets
),
top_tweets AS (
  SELECT 
    account_id,
    json_agg(
      json_build_object(
        'tweet_id', tweet_id,
        'account_id', account_id,
        'created_at', created_at,
        'full_text', full_text,
        'retweet_count', retweet_count,
        'favorite_count', favorite_count,
        'reply_to_tweet_id', reply_to_tweet_id,
        'reply_to_user_id', reply_to_user_id,
        'reply_to_username', reply_to_username,
        'archive_upload_id', archive_upload_id,
        'engagement_score', retweet_count + favorite_count
      ) 
    ) FILTER (WHERE engagement_rank <= 100) as top_engaged_tweets
  FROM ranked_tweets
  GROUP BY account_id
),
mentioned_accounts AS (
  SELECT 
    am.account_id,
    json_agg(
      json_build_object(
        'user_id', am.mentioned_user_id,
        'name', mu.name,
        'screen_name', mu.screen_name,
        'mention_count', am.mention_count
      ) ORDER BY am.mention_count DESC
    ) FILTER (WHERE am.mention_count > 0 AND mention_rank <= 20) as mentioned_accounts
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY mention_count DESC) as mention_rank
    FROM account_mentions
  ) am
  LEFT JOIN public.mentioned_users mu ON mu.user_id = am.mentioned_user_id
  GROUP BY am.account_id
)
SELECT
  a.account_id,
  a.username,
  a.num_tweets,
  a.num_followers,
  COALESCE((
    SELECT COUNT(*)
    FROM public.likes l 
    WHERE l.account_id = a.account_id
  ), 0) AS total_likes,
  COALESCE((
    SELECT COUNT(*)
    FROM public.user_mentions um 
    JOIN public.tweets t ON um.tweet_id = t.tweet_id 
    WHERE t.account_id = a.account_id
  ), 0) AS total_mentions,
  COALESCE(ma.mentioned_accounts, '[]'::json) AS mentioned_accounts,
  COALESCE(tt.top_engaged_tweets, '[]'::json) AS most_favorited_tweets,
  COALESCE(tt.top_engaged_tweets, '[]'::json) AS most_retweeted_tweets,
  COALESCE(tt.top_engaged_tweets, '[]'::json) AS top_engaged_tweets,
  CURRENT_TIMESTAMP AS last_updated
FROM public.account a
LEFT JOIN mentioned_accounts ma ON ma.account_id = a.account_id
LEFT JOIN top_tweets tt ON tt.account_id = a.account_id;

CREATE UNIQUE INDEX idx_account_activity_summary_account_id
ON public.account_activity_summary (account_id);

CREATE TABLE IF NOT EXISTS private.materialized_view_refresh_logs (
    view_name text NOT NULL,
    refresh_started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    refresh_completed_at timestamptz,
    duration_ms bigint
);

CREATE OR REPLACE FUNCTION private.refresh_account_activity_summary()
RETURNS void AS $$
DECLARE
    start_time timestamptz;
    end_time timestamptz;
BEGIN
    start_time := CURRENT_TIMESTAMP;
    
    INSERT INTO private.materialized_view_refresh_logs (view_name)
    VALUES ('account_activity_summary');

    REFRESH MATERIALIZED VIEW public.account_activity_summary;
    
    end_time := CURRENT_TIMESTAMP;
    
    UPDATE private.materialized_view_refresh_logs
    SET refresh_completed_at = end_time,
        duration_ms = EXTRACT(EPOCH FROM (end_time - start_time)) * 1000
    WHERE view_name = 'account_activity_summary'
    AND refresh_started_at = start_time;
END;
$$ LANGUAGE plpgsql;
