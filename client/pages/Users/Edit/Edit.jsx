import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'
import rqst from '../../../helpers/fetch'
import statuses from '../../../helpers/userStatuses'

export default class Edit extends React.Component {
  state = {
    rolesList: [],
    fetchingRoles: true,
    rolesFailMessage: undefined,
  }
  componentDidMount() {
    this.props.fetchUser(this.props.id)
    this.fetchRoles()
  }
  fetchRoles = () => {
    rqst({
      url: '/api/roles',
      onSuccess: ({ result }) => { this.setState(s => ({
        ...s,
        rolesList: result,
        fetchingRoles: false,
      })) },
      onFail: () => { this.setState(s => ({
        ...s,
        rolesFailMessage: 'failed loading roles',
        fetchingRoles: false,
      })) },
      onError: () => { this.setState(s => ({
        ...s,
        rolesFailMessage: 'error while fetching roles',
        fetchingRoles: false,
      })) },
    })
  }
  renderForm() {
    const { user, editForm, submitUser, message, status } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitUser(user)
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    return user !== undefined
      ? (
        <Form onSubmit={handleSubmit}>
          <Form.Input
            value={user.name}
            onChange={handleChange('name')}
            name="name"
            label="User name"
            placeholder="e.g. Robert Diggs"
          />
          <Form.Input
            value={user.login}
            onChange={handleChange('login')}
            name="login"
            label="User login"
            placeholder="e.g. rdiggs"
          />
          <Form.Input
            value={user.password}
            onChange={handleChange('password')}
            name="password"
            type="password"
            label="User password"
            placeholder="type strong password here"
          />
          <Form.Input
            value={user.confirmPassword}
            onChange={handleChange('confirmPassword')}
            name="confirmPassword"
            type="password"
            label="Confirm password"
            placeholder="type password again"
            error={user.confirmPassword !== user.password}
          />
          <Form.Input
            value={user.email}
            onChange={handleChange('email')}
            name="email"
            type="email"
            label="User email"
            placeholder="e.g. robertdiggs@site.domain"
          />
          <Form.Input
            value={user.phone}
            onChange={handleChange('phone')}
            name="phone"
            type="tel"
            label="User phone"
            placeholder="555123456"
          />
          {this.state.fetchingRoles
            ? <Loader content="fetching roles" active />
            : <Form.Select
              value={user.assignedRoles}
              onChange={handleChange('assignedRoles')}
              options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
              name="assignedRoles"
              label="Assigned roles"
              placeholder="select or search roles..."
              multiple
              search
            />}
          <Form.Select
            value={user.status}
            onChange={handleChange('status')}
            options={statuses.map(s => ({ value: s.key, text: s.value }))}
            name="status"
            label="User status"
          />
          <Form.Input
            name="description"
            label="Description"
            placeholder="e.g. very famous NSO employee"
          />
          <Button type="submit" primary>Submit</Button>
          {this.state.rolesFailMessage
            && <div>
              <Message content={this.state.rolesFailMessage} negative />
              <Button onClick={() => { this.fetchRoles() }} type="button">
                try reload roles
              </Button>
            </div>}
          {message && <Message content={message} />}
        </Form>
      ) : <Loader active />
  }
  render() {
    return (
      <div>
        <h2>Edit user</h2>
        {this.renderForm()}
      </div>
    )
  }
}
