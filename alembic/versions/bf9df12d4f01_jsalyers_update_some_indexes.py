"""jsalyers-update-some-indexes

Revision ID: bf9df12d4f01
Revises: 
Create Date: 2020-05-04 15:54:28.863707

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'bf9df12d4f01'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_index('hive_posts_cache_author_permlink_idx', 'hive_posts_cache', ['author', 'permlink'])
    op.create_index('hive_posts_cache_post_id_author_permlink_idx', 'hive_posts_cache', ['post_id', 'author', 'permlink'])


def downgrade():
    op.drop_index('hive_posts_cache_author_permlink_idx')
    op.drop_index('hive_posts_cache_post_id_author_permlink_idx')
