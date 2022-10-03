class AutoDbDisposer(object):
    """Manages whole lifecycle of a database.
    Object of this class should be created by `with` context.
    """

    def __init__(self, db, name):
        self.db = db.clone(name)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, value, traceback):
        if self.db is not None:
            self.db.close()
