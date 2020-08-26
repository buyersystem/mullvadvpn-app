import React, { useCallback } from 'react';
import { colors } from '../../config.json';
import consumePromise from '../../shared/promise';
import { messages } from '../../shared/gettext';
import { formatAccountToken } from '../lib/account';
import Accordion from './Accordion';
import * as AppButton from './AppButton';
import { Brand, HeaderBarSettingsButton } from './HeaderBar';
import ImageView from './ImageView';
import { Container, Header, Layout } from './Layout';
import {
  StyledAccountDropdownItemButton,
  StyledAccountDropdownItemButtonLabel,
  StyledAccountDropdownRemoveIcon,
  StyledAccountInputBackdrop,
  StyledAccountInputGroup,
  StyledDropdownSpacer,
  StyledFooter,
  StyledInput,
  StyledInputButton,
  StyledInputSubmitIcon,
  StyledLoginFooterPrompt,
  StyledLoginForm,
  StyledStatusIcon,
  StyledSubtitle,
  StyledTitle,
} from './LoginStyles';

import { AccountToken } from '../../shared/daemon-rpc-types';
import { LoginState } from '../redux/account/reducers';

interface IProps {
  accountToken?: AccountToken;
  accountHistory: AccountToken[];
  loginState: LoginState;
  openExternalLink: (type: string) => void;
  login: (accountToken: AccountToken) => void;
  resetLoginError: () => void;
  updateAccountToken: (accountToken: AccountToken) => void;
  removeAccountTokenFromHistory: (accountToken: AccountToken) => Promise<void>;
  createNewAccount: () => void;
}

interface IState {
  isActive: boolean;
}

const MIN_ACCOUNT_TOKEN_LENGTH = 10;

export default class Login extends React.Component<IProps, IState> {
  public state: IState = {
    isActive: true,
  };

  private accountInput = React.createRef<HTMLInputElement>();
  private shouldResetLoginError = false;

  constructor(props: IProps) {
    super(props);

    if (props.loginState.type === 'failed') {
      this.shouldResetLoginError = true;
    }
  }

  public componentDidUpdate(prevProps: IProps, _prevState: IState) {
    if (
      this.props.loginState.type !== prevProps.loginState.type &&
      this.props.loginState.type === 'failed' &&
      !this.shouldResetLoginError
    ) {
      this.shouldResetLoginError = true;

      // focus on login field when failed to log in
      this.accountInput.current?.focus();
    }
  }

  public render() {
    const showFooter = this.shouldShowFooter();

    return (
      <Layout>
        <Header>
          <Brand />
          <HeaderBarSettingsButton />
        </Header>
        <Container>
          <StyledLoginForm>
            {this.getStatusIcon()}
            <StyledTitle>{this.formTitle()}</StyledTitle>

            {this.createLoginForm()}
          </StyledLoginForm>

          <StyledFooter show={showFooter}>{this.createFooter()}</StyledFooter>
        </Container>
      </Layout>
    );
  }

  private onFocus = () => {
    this.setState({ isActive: true });
  };

  private onBlur = (e: React.FocusEvent<HTMLInputElement>) => {
    // restore focus if click happened within dropdown
    if (e.relatedTarget) {
      if (this.accountInput.current) {
        this.accountInput.current.focus();
      }
      return;
    }

    this.setState({ isActive: false });
  };

  private onSubmit = () => {
    if (this.accountTokenValid()) {
      this.props.login(this.props.accountToken!);
    }
  };

  private onInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    // reset error when user types in the new account number
    if (this.shouldResetLoginError) {
      this.shouldResetLoginError = false;
      this.props.resetLoginError();
    }

    const accountToken = event.target.value.replace(/[^0-9]/g, '');
    this.props.updateAccountToken(accountToken);
  };

  private onKeyPress = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter') {
      this.onSubmit();
    }
  };

  private formTitle() {
    switch (this.props.loginState.type) {
      case 'logging in':
        return this.props.loginState.method === 'existing_account'
          ? messages.pgettext('login-view', 'Logging in...')
          : messages.pgettext('login-view', 'Creating account...');
      case 'failed':
        return this.props.loginState.method === 'existing_account'
          ? messages.pgettext('login-view', 'Login failed')
          : messages.pgettext('login-view', 'Error');
      case 'ok':
        return this.props.loginState.method === 'existing_account'
          ? messages.pgettext('login-view', 'Logged in')
          : messages.pgettext('login-view', 'Account created');
      default:
        return messages.pgettext('login-view', 'Login');
    }
  }

  private formSubtitle() {
    switch (this.props.loginState.type) {
      case 'failed':
        return this.props.loginState.method === 'existing_account'
          ? this.props.loginState.error.message || messages.pgettext('login-view', 'Unknown error')
          : messages.pgettext('login-view', 'Failed to create account');
      case 'logging in':
        return this.props.loginState.method === 'existing_account'
          ? messages.pgettext('login-view', 'Checking account number')
          : messages.pgettext('login-view', 'Please wait');
      case 'ok':
        return this.props.loginState.method === 'existing_account'
          ? messages.pgettext('login-view', 'Valid account number')
          : messages.pgettext('login-view', 'Logged in');
      default:
        return messages.pgettext('login-view', 'Enter your account number');
    }
  }

  private getStatusIcon() {
    const statusIconPath = this.getStatusIconPath();
    return (
      <StyledStatusIcon>
        {statusIconPath ? <ImageView source={statusIconPath} height={48} width={48} /> : null}
      </StyledStatusIcon>
    );
  }

  private getStatusIconPath(): string | undefined {
    switch (this.props.loginState.type) {
      case 'logging in':
        return 'icon-spinner';
      case 'failed':
        return 'icon-fail';
      case 'ok':
        return 'icon-success';
      default:
        return undefined;
    }
  }

  private allowInteraction() {
    return this.props.loginState.type !== 'logging in' && this.props.loginState.type !== 'ok';
  }

  private accountTokenValid(): boolean {
    const { accountToken } = this.props;
    return accountToken !== undefined && accountToken.length >= MIN_ACCOUNT_TOKEN_LENGTH;
  }

  private shouldShowAccountHistory() {
    return this.allowInteraction() && this.state.isActive && this.props.accountHistory.length > 0;
  }

  private shouldShowFooter() {
    return (
      (this.props.loginState.type === 'none' || this.props.loginState.type === 'failed') &&
      !this.shouldShowAccountHistory()
    );
  }

  private onSelectAccountFromHistory = (accountToken: string) => {
    this.props.updateAccountToken(accountToken);
    this.props.login(accountToken);
  };

  private onRemoveAccountFromHistory = (accountToken: string) => {
    consumePromise(this.removeAccountFromHistory(accountToken));
  };

  private async removeAccountFromHistory(accountToken: AccountToken) {
    try {
      await this.props.removeAccountTokenFromHistory(accountToken);

      // TODO: Remove account from memory
    } catch (error) {
      // TODO: Show error
    }
  }

  private createLoginForm() {
    const allowInteraction = this.allowInteraction();
    const hasError =
      this.props.loginState.type === 'failed' &&
      this.props.loginState.method === 'existing_account';

    return (
      <>
        <StyledSubtitle>{this.formSubtitle()}</StyledSubtitle>
        <StyledAccountInputGroup
          active={allowInteraction && this.state.isActive}
          editable={allowInteraction}
          error={hasError}>
          <StyledAccountInputBackdrop>
            <StyledInput
              placeholder="0000 0000 0000 0000"
              value={this.props.accountToken || ''}
              disabled={!this.allowInteraction()}
              onFocus={this.onFocus}
              onBlur={this.onBlur}
              onChange={this.onInputChange}
              onKeyPress={this.onKeyPress}
              autoFocus={true}
              ref={this.accountInput}
            />
            <StyledInputButton
              visible={this.allowInteraction() && this.accountTokenValid()}
              onClick={this.onSubmit}>
              <StyledInputSubmitIcon
                visible={this.props.loginState.type !== 'logging in'}
                source="icon-arrow"
                height={16}
                width={24}
                tintColor="rgb(255, 255, 255)"
              />
            </StyledInputButton>
          </StyledAccountInputBackdrop>
          <Accordion expanded={this.shouldShowAccountHistory()}>
            {
              <AccountDropdown
                items={this.props.accountHistory.slice().reverse()}
                onSelect={this.onSelectAccountFromHistory}
                onRemove={this.onRemoveAccountFromHistory}
              />
            }
          </Accordion>
        </StyledAccountInputGroup>
      </>
    );
  }

  private createFooter() {
    return (
      <>
        <StyledLoginFooterPrompt>
          {messages.pgettext('login-view', "Don't have an account number?")}
        </StyledLoginFooterPrompt>
        <AppButton.BlueButton
          onClick={this.props.createNewAccount}
          disabled={!this.allowInteraction()}>
          {messages.pgettext('login-view', 'Create account')}
        </AppButton.BlueButton>
      </>
    );
  }
}

interface IAccountDropdownProps {
  items: AccountToken[];
  onSelect: (value: AccountToken) => void;
  onRemove: (value: AccountToken) => void;
}

function AccountDropdown(props: IAccountDropdownProps) {
  const uniqueItems = [...new Set(props.items)];
  return (
    <>
      {uniqueItems.map((token) => {
        const label = formatAccountToken(token);
        return (
          <AccountDropdownItem
            key={token}
            value={token}
            label={label}
            onSelect={props.onSelect}
            onRemove={props.onRemove}
          />
        );
      })}
    </>
  );
}

interface IAccountDropdownItemProps {
  label: string;
  value: AccountToken;
  onRemove: (value: AccountToken) => void;
  onSelect: (value: AccountToken) => void;
}

function AccountDropdownItem(props: IAccountDropdownItemProps) {
  const handleSelect = useCallback(() => {
    props.onSelect(props.value);
  }, [props.onSelect, props.value]);

  const handleRemove = useCallback(() => {
    props.onRemove(props.value);
  }, [props.onRemove, props.value]);

  return (
    <>
      <StyledDropdownSpacer />
      <StyledAccountDropdownItemButton>
        <StyledAccountDropdownItemButtonLabel onClick={handleSelect}>
          {props.label}
        </StyledAccountDropdownItemButtonLabel>
        <StyledAccountDropdownRemoveIcon
          tintColor={colors.blue40}
          tintHoverColor={colors.blue}
          source="icon-close-sml"
          height={16}
          width={16}
          onClick={handleRemove}
        />
      </StyledAccountDropdownItemButton>
    </>
  );
}
