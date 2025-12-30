function xh-update-session
    set token (gcloud auth print-identity-token --audiences=$argv[1])
    xh --session sandbox get https://$argv[2]/ping Authorization:"Bearer $token" X-Oscilar-Env-ID:"$argv[3]"
end
