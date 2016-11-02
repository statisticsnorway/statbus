import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'

export default class Edit extends React.Component {
  componentDidMount() {
    this.props.fetchUser(this.props.id)
  }
  render() {
    const { user, roles, editForm, submitUser, message, status } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitUser(user)
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    return user !== undefined
      ? (
        <Form onSubmit={handleSubmit}>
          <Form.Field>
            <label htmlFor="userNameInput">User name</label>
            <input
              id="userNameInput"
              placeholder="e.g. Robert Diggs"
              name="name"
              value={user.name}
              onChange={handleChange('name')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="userEmailInput">User email</label>
            <input
              id="userEmailInput"
              placeholder="e.g. robertdiggs@site.domain"
              name="email"
              type="email"
              value={user.email}
              onChange={handleChange('email')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="userLoginInput">User login</label>
            <input
              id="userLoginInput"
              placeholder="e.g. rdiggs"
              name="login"
              value={user.login}
              onChange={handleChange('login')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="userPasswordInput">User password</label>
            <input
              id="userPasswordInput"
              placeholder="type strong password here"
              name="password"
              type="password"
              value={user.password}
              onChange={handleChange('password')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="userConfirmPasswordInput">User confirmPassword</label>
            <input
              id="userConfirmPasswordInput"
              placeholder="e.g. robertdiggs@site.domain"
              name="confirmPassword"
              type="password"
              value={user.confirmPassword}
              onChange={handleChange('confirmPassword')}
            />
          </Form.Field>
          <Form.Field>
            <label htmlFor="userDescriptionInput">Description</label>
            <input
              id="userDescriptionInput"
              placeholder="e.g. very famous NSO employee"
              name="description"
              value={user.description}
              onChange={handleChange('description')}
            />
          </Form.Field>
        </Form>
      ) : <Loader active />
  }
}
