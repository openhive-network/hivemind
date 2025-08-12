-- Helper function to preprocess search queries for ParadeDB
-- Handles quoted phrases, +/- prefixes, field specifications, and escaping

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.preprocess_search_query;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.preprocess_search_query(_pattern TEXT)
RETURNS TEXT
LANGUAGE plpython3u
IMMUTABLE
SECURITY DEFINER
AS $$
import re

def preprocess_search_query(pattern):
    """
    Preprocesses user search queries to generate valid ParadeDB query syntax.
    
    Handles:
    - Quoted phrases: "hello world" -> exact phrase search  
    - Must/mustnot: +term -term
    - Field-specific: title:term or body:term
    - Default: searches both title and body fields
    """
    if not pattern or not pattern.strip():
        return ''
    
    # First pass: fix unclosed quotes by adding closing quotes at the end
    quote_count = pattern.count('"')
    if quote_count % 2 != 0:
        pattern = pattern + '"'
    
    # Tokenize the input while preserving quoted phrases
    tokens = []
    i = 0
    while i < len(pattern):
        # Skip whitespace
        while i < len(pattern) and pattern[i].isspace():
            i += 1
        if i >= len(pattern):
            break
            
        # Check for quoted phrase
        if pattern[i] == '"':
            j = i + 1
            phrase_parts = []
            while j < len(pattern):
                if pattern[j] == '"':
                    # Found closing quote
                    phrase = ''.join(phrase_parts)
                    # Escape any quotes within the phrase
                    phrase = phrase.replace('"', '\\"')
                    tokens.append(('phrase', f'"{phrase}"'))
                    i = j + 1
                    break
                elif pattern[j] == '\\' and j + 1 < len(pattern):
                    # Handle escaped characters
                    phrase_parts.append(pattern[j:j+2])
                    j += 2
                else:
                    phrase_parts.append(pattern[j])
                    j += 1
            else:
                # Should not happen due to quote fixing above
                i = j
                
        # Check for must/mustnot prefix
        elif pattern[i] == '+':
            j = i + 1
            while j < len(pattern) and not pattern[j].isspace():
                j += 1
            term = pattern[i+1:j]
            if term:
                tokens.append(('must', term))
            i = j
            
        elif pattern[i] == '-':
            j = i + 1
            while j < len(pattern) and not pattern[j].isspace():
                j += 1
            term = pattern[i+1:j]
            if term:
                tokens.append(('mustnot', term))
            i = j
            
        # Check for field:value pattern
        else:
            j = i
            while j < len(pattern) and not pattern[j].isspace():
                j += 1
            word = pattern[i:j]
            
            # Check if it's a field specification
            if ':' in word and word.split(':', 1)[0] in ['title', 'body']:
                field, value = word.split(':', 1)
                # Check if value starts with a quote (field:"quoted value")
                if value.startswith('"'):
                    # Find the closing quote
                    k = j
                    if not value.endswith('"'):
                        # Continue searching for closing quote
                        while k < len(pattern):
                            if pattern[k] == '"':
                                value = pattern[i:k+1].split(':', 1)[1]
                                j = k + 1
                                break
                            k += 1
                    # Process the field:value
                    if value.startswith('"') and value.endswith('"'):
                        inner = value[1:-1]
                        inner = inner.replace('"', '\\"')
                        tokens.append(('field', f'{field}:"{inner}"'))
                    else:
                        tokens.append(('field', f'{field}:{value}'))
                else:
                    tokens.append(('field', word))
            else:
                # Regular word
                if word and word != '"':  # Skip standalone quotes
                    tokens.append(('word', word))
            i = j
    
    if not tokens:
        return ''
    
    # Build the ParadeDB query
    query_parts = []
    
    for token_type, value in tokens:
        if token_type == 'field':
            # Field-specific search - use as-is
            query_parts.append(value)
            
        elif token_type == 'phrase':
            # Quoted phrase - search in both fields
            query_parts.append(f'(title:{value} OR body:{value})')
            
        elif token_type == 'must':
            # Must have term - search in both fields with + prefix
            # Escape quotes in the term if present
            if '"' in value:
                value = value.replace('"', '\\"')
            query_parts.append(f'+(title:{value} OR body:{value})')
            
        elif token_type == 'mustnot':
            # Must not have term - search in both fields with - prefix
            # Escape quotes in the term if present
            if '"' in value:
                value = value.replace('"', '\\"')
            query_parts.append(f'-(title:{value} OR body:{value})')
            
        elif token_type == 'word':
            # Regular word - search in both fields
            # Escape quotes if present
            if '"' in value:
                value = value.replace('"', '\\"')
            query_parts.append(f'(title:{value} OR body:{value})')
    
    # Join with AND by default (like Google)
    # Must/mustnot terms are already prefixed, so they work correctly
    result = ' AND '.join([q for q in query_parts if not q.startswith(('+', '-'))])
    
    # Add must/mustnot terms at the end
    must_terms = ' '.join([q for q in query_parts if q.startswith(('+', '-'))])
    if must_terms:
        if result:
            result = f'{result} {must_terms}'
        else:
            result = must_terms
    
    return result

# Call the function
return preprocess_search_query(_pattern)
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION hivemind_postgrest_utilities.preprocess_search_query TO hivemind;
GRANT EXECUTE ON FUNCTION hivemind_postgrest_utilities.preprocess_search_query TO hivemind_user;