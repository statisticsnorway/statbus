import React from 'react'
import { Button, Form, Loader } from 'semantic-ui-react'

import rqst from '../../../helpers/request'

export default class CreateForm extends React.Component {
  state = {
    standardDataAccess: [],
    systemFunctions: [],
    fetchingStandardDataAccess: true,
    fetchingSystemFunctions: true,
    standardDataAccessMessage: undefined,
    systemFunctionsFailMessage: undefined,
  }
  componentDidMount() {
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
    const { submitRole } = this.props
    const handleSubmit = (e, serialized) => {
      e.preventDefault()
      submitRole(serialized)
    }
    return (
      <div>
        <h2>Create new role</h2>
        <Form onSubmit={handleSubmit}>
          <Form.Input
            name="name"
            label="Role name"
            placeholder="e.g. Web Site Visitor"
          />
          <Form.Input
            name="description"
            label="Description"
            placeholder="e.g. Ordinary website user"
          />
          {this.state.fetchingStandardDataAccess
            ? <Loader content="fetching standard data access" />
            : <Form.Select
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
              options={this.state.systemFunctions.map(r => ({ value: r.key, text: r.value }))}
              name="accessToSystemFunctions"
              label="Access to system functions"
              placeholder="select or search system functions..."
              multiple
              search
            />}
          <Button type="submit" primary>Submit</Button>
        </Form>
      </div>
    )
  }
}
