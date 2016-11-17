import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'

import rqst from '../../../helpers/fetch'

export default class Edit extends React.Component {
  state = {
    standardDataAccess: [],
    systemFunctions: [],
    fetchingStandardDataAccess: true,
    fetchingSystemFunctions: true,
    standardDataAccessMessage: undefined,
    systemFunctionsFailMessage: undefined,
  }
  componentDidMount() {
    this.props.fetchRole(this.props.id)
    this.fetchStandardDataAccess()
    this.fetchSystemFunctions()
  }
  fetchStandardDataAccess() {
    rqst({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => { this.setState(s => ({
        ...s,
        standardDataAccess: result,
        fetchingStandardDataAccess: false,
      })) },
      onFail: () => { this.setState(s => ({
        ...s,
        standardDataAccessMessage: 'failed loading standard data access',
        fetchingStandardDataAccess: false,
      })) },
      onError: () => { this.setState(s => ({
        ...s,
        standardDataAccessFailMessage: 'error while fetching standard data access',
        fetchingStandardDataAccess: false,
      })) },
    })
  }
  fetchSystemFunctions() {
    rqst({
      url: '/api/accessAttributes/systemFunctions',
      onSuccess: (result) => { this.setState(s => ({
        ...s,
        systemFunctions: result,
        fetchingSystemFunctions: false,
      })) },
      onFail: () => { this.setState(s => ({
        ...s,
        systemFunctionsFailMessage: 'failed loading system functions',
        fetchingSystemFunctions: false,
      })) },
      onError: () => { this.setState(s => ({
        ...s,
        systemFunctionsFailMessage: 'error while fetching system functions',
        fetchingSystemFunctions: false,
      })) },
    })
  }
  render() {
    const { role, editForm, submitRole, message, status } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitRole(role)
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    const handleSelect = (e, { name, value }) => { editForm({ propName: name, value }) }
    return (
      <div>
        <h2>Edit role</h2>
        {role === undefined
          ? <Loader active />
          : <Form onSubmit={handleSubmit}>
            <Form.Input
              value={role.name}
              onChange={handleChange('name')}
              name="name"
              label="Role name"
              placeholder="e.g. Web Site Visitor"
            />
            <Form.Input
              value={role.description}
              onChange={handleChange('description')}
              name="description"
              label="Description"
              placeholder="e.g. Ordinary website user"
            />
            {this.state.fetchingStandardDataAccess
              ? <Loader content="fetching standard data access" />
              : <Form.Select
                value={role.standardDataAccess}
                onChange={handleSelect}
                options={this.state.standardDataAccess.map(r => ({ value: r.key, text: r.value }))}
                name="standardDataAccess"
                label="Standard data access"
                placeholder="select or search standard data access..."
                multiple
                search
              />}
            {this.state.fetchingSystemFunctions
              ? <Loader content="fetching system functions" />
              : <Form.Select
                value={role.accessToSystemFunctions}
                onChange={handleSelect}
                options={this.state.systemFunctions.map(x => ({ value: x.key, text: x.value }))}
                name="accessToSystemFunctions"
                label="Access to system functions"
                placeholder="select or search system functions..."
                multiple
                search
              />}
            <Button type="submit" primary>Submit</Button>
            {message && <Message content={message} negative />}
          </Form>}
      </div>
    )
  }
}
