
#!/bin/bash
##################################################################################################
# Script Name : awsMfa.sh (originally generateMFASecurityToken.sh)
# Original Author : Prasad Domala (prasad.domala@gmail.com)
# Original Source : http://prasaddomala.com/configure-multi-factor-authentication-mfa-with-aws-cli/
##################################################################################################

print_help() {
    printf "Usage: $0 BaseProfileName\n\n"
    printf "\n*** Prerequisites ***"
    printf "\n1) You must update profiles in ~/.aws/credentials to have the Account ID (can't be Account alias) and User ID in the following format:"
    printf "\n<BaseProfileName>-accountId = <Account ID for that profile>\n<BaseProfileName>-userId = <User ID for that profile>"
    printf "\n(Duplicates will cause a parsing error that can be seen when asking for the Token Code)"
    printf "\nExample:"
    printf "\n[default]"
    printf "\naws_access_key_id = AKIAIO...."
    printf "\naws_secret_access_key = zceCkZf7....."
    printf "\ndefault-accountId = 3075029..."
    printf "\ndefault-userId = jdoe"
    printf "\n\n2)You must also have the region set for that profile to use the STS Service"
    printf "\n\n\nExample usage with above (default) profile: $0 default"
    printf "\nThe script will parse the credentials file, establish the ARN for your virtual MFA, and prompt you for a token code."
    printf "\nAfter you enter the code, it will try to generate temporary credentials for you.  It will then store the credentials "
    printf "in you credentials file under the profile name <BaseProfileName>-MFA and will store the expiration of your credentials in the "
    printf "config file for that same profile.  If your token has not expired, it will not try to generate a new one for you.  It "
    printf "will set the default region of the temporary profile to the Base profile region and do the same for default output if set."
    printf "\nThe script will also output an alias command for easy copy/pasting to use in place of the 'aws' command or quickly switch profiles."
    printf "\n\n"
}

# Validate inputs
if [ "$#" -ne 1 ]; then
    print_help
    exit
fi

# Get profile names from arguements
BASE_PROFILE_NAME=$1
MFA_PROFILE_NAME=$1-MFA

# Check to see if we already have a STS delivered temporary profile
# Expiration Time: Each SessionToken will have an expiration time which by default is 12 hours and
# can range between 15 minutes and 36 hours
printf "Checking for existing temporary credentials for '${BASE_PROFILE_NAME}'...\n"
MFA_PROFILE_EXISTS=`more ~/.aws/credentials | grep $MFA_PROFILE_NAME | wc -l`
if [ $MFA_PROFILE_EXISTS -eq 1 ]; then
    EXPIRATION_TIME=$(aws configure get expiration --profile $MFA_PROFILE_NAME)
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ "$EXPIRATION_TIME" > "$NOW" ]]; then
        printf "The Session Token is still valid. New Security Token not required, use it by calling:\n"
        printf "\naws --profile ${MFA_PROFILE_NAME}\nOr alias it:\nalias mfaws=\"aws --profile ${MFA_PROFILE_NAME}\"\n\nExiting.\n"
        exit
    fi
fi

# Check to see if the base profile exists
printf "Checking for '${BASE_PROFILE_NAME}' MFA serial details....\n"
BASE_PROFILE_EXISTS=`more ~/.aws/credentials | grep $BASE_PROFILE_NAME | wc -l`
if [ $BASE_PROFILE_EXISTS -eq 0 ]; then
    print_help
    printf "\n\nERROR: Base profile '${BASE_PROFILE_NAME}' does not exist, exiting!\n"
    exit 1
fi

MFA_ACCT_ID=$(cat ~/.aws/credentials | grep "${BASE_PROFILE_NAME}-accountId" | cut -d'=' -f2 | tr -d '[:space:]')
if [ -z $MFA_ACCT_ID ]; then
    print_help
    printf "\n\nERROR: No Account ID found for '$BASE_PROFILE_NAME', aborting.\n"
    exit 1
fi
MFA_USER_ID=$(cat ~/.aws/credentials | grep "${BASE_PROFILE_NAME}-userId" | cut -d'=' -f2 | tr -d '[:space:]')
if [ -z $MFA_USER_ID ]; then
    print_help
    printf "\n\nERROR: No User ID found for '$BASE_PROFILE_NAME', aborting.\n"
    exit 1
fi
# MFA Serial: Specify MFA_SERIAL of IAM User
# Example: arn:aws:iam::123456789123:mfa/iamusername
MFA_SERIAL="arn:aws:iam::${MFA_ACCT_ID}:mfa/${MFA_USER_ID}"


# Set default region (mandatory)
printf "Checking '${BASE_PROFILE_NAME}' configuration...\n"
PROFILE_REGION=$(aws configure --profile "$BASE_PROFILE_NAME" get region)
if [ $? -ne 0 ]; then
    print_help
    printf "\n\nERROR: Region setting not found for '$BASE_PROFILE_NAME', aborting.\n"
    exit 1
fi
printf "'${BASE_PROFILE_NAME}' region is set to: ${PROFILE_REGION}\n"
# Grab profile output if it exists (optional)
PROFILE_OUTPUT=$(aws configure --profile "$BASE_PROFILE_NAME" get output)
if [ ! -z $PROFILE_OUTPUT ]; then
    printf "'${BASE_PROFILE_NAME}' default output is set to: ${PROFILE_OUTPUT}\n"
fi

read -p "Enter current token code for MFA Device ($MFA_SERIAL): " TOKEN_CODE
printf "Attempting to generating new IAM STS Token...\n"
read -r AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN EXPIRATION AWS_ACCESS_KEY_ID < <(aws sts get-session-token --profile $BASE_PROFILE_NAME --output text --query 'Credentials.[SecretAccessKey, SessionToken, Expiration, AccessKeyId]' --serial-number $MFA_SERIAL --token-code $TOKEN_CODE)
if [ $? -ne 0 ];then
    printf "\nAn error occured. AWS credentials file not updated, please check configuration and try again.\n"
    exit 1
fi
printf "STS Session Token successfully generated, attempting to store profile...\n"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile $MFA_PROFILE_NAME
aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile $MFA_PROFILE_NAME
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile $MFA_PROFILE_NAME
printf "Credentials stored in MFA profile '${MFA_PROFILE_NAME}'...\n"
aws configure set expiration "$EXPIRATION" --profile $MFA_PROFILE_NAME
printf "Expiration stored in '${MFA_PROFILE_NAME}' config...\n"
aws configure set region "$PROFILE_REGION" --profile $MFA_PROFILE_NAME
printf "'${MFA_PROFILE_NAME}' default region set to: ${PROFILE_REGION}\n"
if [ ! -z $PROFILE_OUTPUT ]; then
    aws configure set output "$PROFILE_OUTPUT" --profile $MFA_PROFILE_NAME
    printf "'${MFA_PROFILE_NAME}' default output set to: ${PROFILE_OUTPUT}\n"
fi
printf "Credentials and config file updated with details for '${MFA_PROFILE_NAME}'.  Use it by calling:\n"
printf "        aws --profile ${MFA_PROFILE_NAME}\n"
printf "Or alias it and use it in place of 'aws':\n"
printf "        alias mfaws=\"aws --profile ${MFA_PROFILE_NAME}\"\n"
printf "You can also set the environment variables by using the following commands (if you keep the leading space, it's not saved to bash history with default history settings):\n"
printf "        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID\n"
printf "        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY\n"
printf "        export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN\n\n"
exit 0
