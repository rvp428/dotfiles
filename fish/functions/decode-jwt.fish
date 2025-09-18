function decode-jwt
    if test (count $argv) -eq 0
        set token (pbpaste)
    else
        set token $argv[1]
    end
    set parts (echo $token | string split .)
    if test (count $parts) -lt 2
        echo "decode-jwt: not a valid JWT" >&2
        return 1
    end
    echo $parts[2] | base64 -D | jq
end
