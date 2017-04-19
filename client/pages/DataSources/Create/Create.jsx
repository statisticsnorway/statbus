import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'

import Form from 'components/Form'
import * as enums from 'helpers/dataSourceEnums'
import MappingsEditor from '../MappingsEditor'
import schema from '../schema'

const priorities = [...enums.priorities].map(([value, text]) => ({ value, text }))
const operations = [...enums.operations].map(([value, text]) => ({ value, text }))
const { Button, Select, Text } = Form
const unitTypeArray = arrayOf(shape({
  name: string,
})).isRequired

class Create extends React.Component {

  static propTypes = {
    columns: shape({
      enterpriseGroup: unitTypeArray,
      enterpriseUnit: unitTypeArray,
      legalUnit: unitTypeArray,
      localUnit: unitTypeArray,
    }),
    localize: func.isRequired,
    actions: shape({
      fetchColumns: func.isRequired,
      submitData: func.isRequired,
    }).isRequired,
  }

  static defaultProps = {
    columns: [],
  }

  state = {
    formData: {
      name: '',
      description: '',
      allowedOperations: '',
      attributesToCheck: [],
      priority: 0,
      restrictions: '',
      variablesMapping: [],
    },
    attributes: [],
  }

  componentDidMount() {
    this.props.actions.fetchColumns()
  }

  handleMappingsChange = (value) => {
    this.setState(prev =>
      ({ formData: { ...prev.formData, variablesMapping: value } }))
  }

  handleEdit = (_, { name, value }) => {
    this.setState(prev =>
      ({ formData: { ...prev.formData, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.actions.submitData(this.state.formData)
  }

  render() {
    const { columns, localize } = this.props
    const {
      formData: {
        name, description, allowedOperations, priority,
        attributesToCheck, restrictions, variablesMapping,
      },
      attributes: allAttributes,
    } = this.state
    return (
      <Form schema={schema}>
        <Text name="name" value={name} onChange={this.handleEdit} />
        <Form.Error at={'name'} />
        <Text name="description" value={description} onChange={this.handleEdit} />
        {/*<Form.Error at={'description'} />*/}
        <Text name="restrictions" value={restrictions} onChange={this.handleEdit} />
        {/*<Form.Error at={'restrictions'} />*/}
        <Select
          name="attributesToCheck"
          value={attributesToCheck}
          onChange={this.handleEdit}
          options={allAttributes}
          multiple
        />
        {/*<Form.Error at={'attributesToCheck'} />*/}
        <Select
          name="allowedOperations"
          value={allowedOperations}
          onChange={this.handleEdit}
          options={operations}
        />
        {/*<Form.Error at={'allowedOperations'} />*/}
        <Select
          name="priority"
          value={priority}
          onChange={this.handleEdit}
          options={priorities}
        />
        {/*<Form.Error at={'priority'} />
        <MappingsEditor
          name="variablesMapping"
          value={variablesMapping}
          onChange={this.handleMappingsChange}
          attributes={allAttributes}
          columns={columns.legalUnit || []}
        />
        <Form.Error at={'variablesMapping'} />*/}
        <Button type="submit">{localize('Save')}</Button>
      </Form>
    )
  }
}

export default Create
