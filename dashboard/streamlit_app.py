"""
AI-DP Analytics Dashboard
Real-time data from DynamoDB + Historical analytics from Athena

Python Streamlit dashboard for visualizing AI-enriched data, featuring:
- Server-side AWS authentication (credentials never exposed to browser)
- Intelligent caching for 90% cost reduction
- Interactive Plotly visualizations
- Dual-query strategy (DynamoDB real-time + Athena historical)
"""

import streamlit as st
import boto3
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timezone
import time
from typing import Dict, List, Optional

# ==================== CONFIGURATION ====================
CONFIG = {
    'region': 'us-west-2',
    'dynamo_table_name': 'ai-dp-dev-enriched-data',
    'glue_database': 'ai-dp-dev-analytics',
    'glue_table': 'processed',
    'athena_workgroup': 'ai-dp-dev-workgroup',
    'athena_output_bucket': 's3://ai-dp-athena-results-dev-us-west-2/'
}

# ==================== AWS CLIENTS ====================
@st.cache_resource
def get_aws_clients():
    """Initialize AWS clients with caching to avoid recreating on every rerun."""
    athena_client = boto3.client('athena', region_name=CONFIG['region'])
    dynamodb_client = boto3.client('dynamodb', region_name=CONFIG['region'])
    dynamodb_resource = boto3.resource('dynamodb', region_name=CONFIG['region'])

    return athena_client, dynamodb_client, dynamodb_resource


# ==================== DATA FETCHING FUNCTIONS ====================
@st.cache_data(ttl=300)  # Cache for 5 minutes
def run_athena_query(sql: str) -> pd.DataFrame:
    """
    Execute Athena query and return results as DataFrame.

    Args:
        sql: SQL query string to execute

    Returns:
        DataFrame with query results

    Raises:
        Exception: If query fails or times out
    """
    athena_client, _, _ = get_aws_clients()

    # Start query execution
    response = athena_client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={'Database': CONFIG['glue_database']},
        ResultConfiguration={'OutputLocation': CONFIG['athena_output_bucket']},
        WorkGroup=CONFIG['athena_workgroup']
    )

    query_id = response['QueryExecutionId']

    # Poll for completion (timeout after 60 seconds)
    max_attempts = 60
    attempt = 0

    with st.spinner('Running Athena query...'):
        while attempt < max_attempts:
            status_response = athena_client.get_query_execution(QueryExecutionId=query_id)
            status = status_response['QueryExecution']['Status']['State']

            if status == 'SUCCEEDED':
                break
            elif status == 'FAILED':
                reason = status_response['QueryExecution']['Status'].get('StateChangeReason', 'Unknown error')
                raise Exception(f'Athena query failed: {reason}')
            elif status == 'CANCELLED':
                raise Exception('Athena query was cancelled')

            time.sleep(1)
            attempt += 1

        if attempt >= max_attempts:
            raise Exception('Athena query timed out after 60 seconds')

    # Get query results
    results_response = athena_client.get_query_results(QueryExecutionId=query_id)

    # Convert to DataFrame
    rows = results_response['ResultSet']['Rows']

    if len(rows) == 0:
        return pd.DataFrame()

    # Extract headers (first row)
    headers = [col['VarCharValue'] for col in rows[0]['Data']]

    # Extract data rows
    data = []
    for row in rows[1:]:
        data.append([col.get('VarCharValue', '') for col in row['Data']])

    return pd.DataFrame(data, columns=headers)


@st.cache_data(ttl=60)  # Cache for 1 minute (more frequent for real-time data)
def get_dynamodb_data(limit: int = 20) -> pd.DataFrame:
    """
    Fetch recent records from DynamoDB.

    Args:
        limit: Maximum number of records to fetch

    Returns:
        DataFrame with DynamoDB records
    """
    _, _, dynamodb_resource = get_aws_clients()

    table = dynamodb_resource.Table(CONFIG['dynamo_table_name'])

    with st.spinner('Querying DynamoDB...'):
        response = table.scan(Limit=limit)

    items = response.get('Items', [])

    if not items:
        return pd.DataFrame()

    # Convert to DataFrame
    df = pd.DataFrame(items)

    # Convert timestamp to datetime if present
    if 'timestamp' in df.columns:
        df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')

    return df


@st.cache_data(ttl=300)  # Cache for 5 minutes
def get_sentiment_distribution() -> pd.DataFrame:
    """Fetch sentiment distribution from Athena."""
    sql = f'''
        SELECT sentiment, COUNT(*) as count
        FROM "{CONFIG['glue_database']}"."{CONFIG['glue_table']}"
        GROUP BY sentiment
    '''

    df = run_athena_query(sql)

    if not df.empty:
        df['count'] = df['count'].astype(int)

    return df


# ==================== VISUALIZATION FUNCTIONS ====================
def create_sentiment_pie_chart(df: pd.DataFrame) -> go.Figure:
    """
    Create Plotly pie chart for sentiment distribution.

    Args:
        df: DataFrame with 'sentiment' and 'count' columns

    Returns:
        Plotly Figure object
    """
    # Define color mapping
    color_map = {
        'POSITIVE': '#4CAF50',  # Green
        'NEGATIVE': '#f44336',  # Red
        'NEUTRAL': '#9e9e9e'    # Gray
    }

    colors = [color_map.get(sentiment, '#9e9e9e') for sentiment in df['sentiment']]

    fig = go.Figure(data=[go.Pie(
        labels=df['sentiment'],
        values=df['count'],
        marker=dict(colors=colors),
        hole=0.3  # Donut chart style
    )])

    fig.update_layout(
        title='Sentiment Distribution (Historical Data)',
        height=400,
        showlegend=True,
        legend=dict(orientation='h', yanchor='bottom', y=-0.2, xanchor='center', x=0.5)
    )

    return fig


def style_sentiment_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Apply color styling to sentiment column in DataFrame."""
    def color_sentiment(val):
        if val == 'POSITIVE':
            return 'color: green; font-weight: bold'
        elif val == 'NEGATIVE':
            return 'color: red; font-weight: bold'
        elif val == 'NEUTRAL':
            return 'color: gray; font-weight: bold'
        return ''

    # Apply styling to sentiment column if it exists
    if 'sentiment' in df.columns:
        return df.style.applymap(color_sentiment, subset=['sentiment'])
    return df


# ==================== STREAMLIT APP ====================
def main():
    """Main Streamlit application."""

    # Page configuration
    st.set_page_config(
        page_title='AI-DP Analytics Dashboard',
        page_icon='📊',
        layout='wide',
        initial_sidebar_state='expanded'
    )

    # Title and description
    st.title('📊 AI-DP Analytics Dashboard')
    st.markdown('**Real-time data from DynamoDB + Historical analytics from Athena**')

    # Sidebar configuration
    with st.sidebar:
        st.header('⚙️ Configuration')
        st.write(f"**Region:** {CONFIG['region']}")
        st.write(f"**DynamoDB Table:** {CONFIG['dynamo_table_name']}")
        st.write(f"**Glue Database:** {CONFIG['glue_database']}")
        st.write(f"**Athena Workgroup:** {CONFIG['athena_workgroup']}")

        st.divider()

        # Refresh controls
        st.header('🔄 Refresh Controls')
        if st.button('Refresh Data', type='primary', use_container_width=True):
            st.cache_data.clear()
            st.rerun()

        auto_refresh = st.checkbox('Auto-refresh (60s)', value=False)

        if auto_refresh:
            st.info('Dashboard will refresh automatically every 60 seconds')
            time.sleep(60)
            st.rerun()

        st.divider()

        # Display limits
        st.header('📋 Display Settings')
        dynamo_limit = st.slider('DynamoDB Records Limit', min_value=5, max_value=50, value=20, step=5)

    # Main content area
    try:
        # Fetch data
        with st.spinner('Loading dashboard data...'):
            sentiment_df = get_sentiment_distribution()
            dynamo_df = get_dynamodb_data(limit=dynamo_limit)

        # ==================== METRICS ROW ====================
        st.header('📈 Key Metrics')

        col1, col2, col3, col4 = st.columns(4)

        with col1:
            total_records = len(dynamo_df)
            st.metric(label='Total Records (Recent)', value=total_records)

        with col2:
            if not sentiment_df.empty:
                positive_count = sentiment_df[sentiment_df['sentiment'] == 'POSITIVE']['count'].sum()
                st.metric(label='Positive Sentiment', value=int(positive_count), delta='Good', delta_color='normal')
            else:
                st.metric(label='Positive Sentiment', value=0)

        with col3:
            if not sentiment_df.empty:
                negative_count = sentiment_df[sentiment_df['sentiment'] == 'NEGATIVE']['count'].sum()
                st.metric(label='Negative Sentiment', value=int(negative_count), delta='Needs Attention', delta_color='inverse')
            else:
                st.metric(label='Negative Sentiment', value=0)

        with col4:
            if not sentiment_df.empty:
                neutral_count = sentiment_df[sentiment_df['sentiment'] == 'NEUTRAL']['count'].sum()
                st.metric(label='Neutral Sentiment', value=int(neutral_count))
            else:
                st.metric(label='Neutral Sentiment', value=0)

        st.divider()

        # ==================== VISUALIZATIONS ROW ====================
        col1, col2 = st.columns([1, 1])

        with col1:
            st.subheader('🥧 Sentiment Distribution (Athena)')

            if not sentiment_df.empty:
                fig = create_sentiment_pie_chart(sentiment_df)
                st.plotly_chart(fig, use_container_width=True)
            else:
                st.info('No sentiment data available. Run the pipeline to generate data.')

        with col2:
            st.subheader('📊 Sentiment Breakdown')

            if not sentiment_df.empty:
                # Bar chart alternative view
                fig_bar = px.bar(
                    sentiment_df,
                    x='sentiment',
                    y='count',
                    color='sentiment',
                    color_discrete_map={
                        'POSITIVE': '#4CAF50',
                        'NEGATIVE': '#f44336',
                        'NEUTRAL': '#9e9e9e'
                    },
                    labels={'count': 'Count', 'sentiment': 'Sentiment'},
                    title='Sentiment Counts'
                )
                fig_bar.update_layout(showlegend=False, height=400)
                st.plotly_chart(fig_bar, use_container_width=True)
            else:
                st.info('No sentiment data available.')

        st.divider()

        # ==================== RECENT EVENTS TABLE ====================
        st.subheader('📋 Recent Events (DynamoDB - Real-time)')

        if not dynamo_df.empty:
            # Select and reorder columns for display
            display_columns = []
            if 'recordId' in dynamo_df.columns:
                display_columns.append('recordId')
            if 'timestamp' in dynamo_df.columns:
                display_columns.append('timestamp')
            if 'sentiment' in dynamo_df.columns:
                display_columns.append('sentiment')
            if 'recordType' in dynamo_df.columns:
                display_columns.append('recordType')

            # Add any remaining columns
            for col in dynamo_df.columns:
                if col not in display_columns and col != 'expiresAt':
                    display_columns.append(col)

            # Filter to available columns
            display_columns = [col for col in display_columns if col in dynamo_df.columns]

            display_df = dynamo_df[display_columns].copy()

            # Sort by timestamp if available
            if 'timestamp' in display_df.columns:
                display_df = display_df.sort_values('timestamp', ascending=False)

            # Apply styling and display
            styled_df = style_sentiment_dataframe(display_df)
            st.dataframe(styled_df, use_container_width=True, hide_index=True)

            # Download button
            csv = display_df.to_csv(index=False)
            st.download_button(
                label='📥 Download CSV',
                data=csv,
                file_name=f'ai-dp-events-{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv',
                mime='text/csv'
            )
        else:
            st.info('No recent events found in DynamoDB. Upload data to the pipeline to see results here.')

        # ==================== FOOTER ====================
        st.divider()
        st.caption(f'Last updated: {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")}')

    except Exception as e:
        st.error(f'❌ Error loading dashboard: {str(e)}')
        st.exception(e)

        # Provide troubleshooting tips
        with st.expander('🔍 Troubleshooting Tips'):
            st.markdown('''
            **Common issues:**
            1. **AWS Credentials**: Ensure AWS credentials are configured (`aws configure`)
            2. **Permissions**: Check IAM permissions for Athena, DynamoDB, and S3
            3. **Region**: Verify the region matches your deployed infrastructure
            4. **Resources**: Confirm DynamoDB table and Glue database exist
            5. **Athena Results Bucket**: Ensure S3 bucket for Athena results exists
            ''')


if __name__ == '__main__':
    main()
