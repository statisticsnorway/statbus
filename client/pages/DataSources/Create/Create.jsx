import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'
import { map } from 'ramda'
import { Accordion, Icon, Message } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'
import { Link } from 'react-router'

import MappingsEditor from 'components/DataSourceMapper'
import Form from 'components/Form'
import * as enums from 'helpers/dataSourceEnums'
import statUnitTypes from 'helpers/statUnitTypes'
import toCamelCase from 'helpers/stringToCamelCase'
import { parseCSV, parseXML } from 'helpers/parseDataSourceAttributes'
import schema from '../schema'
import styles from './styles.pcss'

const unmap = map(([value, text]) => ({ value, text }))
const statunitOptions = unmap([...statUnitTypes]).filter(x => x.value < 4)
const priorities = unmap([...enums.priorities])
const operations = unmap([...enums.operations])

const getTypeKeyForColumns = key => toCamelCase(statUnitTypes.get(key))

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
    }).isRequired,
    localize: func.isRequired,
    actions: shape({
      fetchColumns: func.isRequired,
      submitData: func.isRequired,
    }).isRequired,
  }

  state = {
    formData: schema.default(),
    attributes: [],
    file: undefined,
    fileError: undefined,
  }

  componentDidMount() {
    this.props.actions.fetchColumns()
  }

  componentWillUnmount() {
    this.revokeCurrentFileUrl()
  }

  getLocalizedOptions() {
    const localizeArray = map(x => ({ ...x, text: this.props.localize(x.text) }))
    return {
      statUnitType: localizeArray(statunitOptions),
      attributesToCheck: localizeArray(this.state.attributes.map(x => ({ text: x, value: x }))),
      allowedOperations: localizeArray(operations),
      priorities: localizeArray(priorities),
    }
  }

  revokeCurrentFileUrl() {
    const { file } = this.state
    if (file) URL.revokeObjectURL(file.preview)
  }

  handleDropFile = (files) => {
    const file = files[0]
    const reader = new FileReader()
    try {
      reader.onload = (e) => {
        this.revokeCurrentFileUrl()
        const attributes = file.name.endsWith('.xml')
          ? parseXML(e.target.result)
          : file.name.endsWith('.csv')
            ? parseCSV(e.target.result)
            : []
        if (attributes.length === 0) {
          this.setState(prev => ({
            fileError: this.props.localize('ParseAttributesNotFound'),
            formData: { ...prev.formData, variablesMapping: [] },
          }))
        } else {
          this.setState(prev => ({
            attributes,
            file,
            fileError: undefined,
            formData: { ...prev.formData, variablesMapping: [] },
          }))
        }
      }
      reader.readAsText(file)
    } catch (err) {
      this.setState({ fileError: this.props.localize('ParseFileError') })
    }
  }

  handleMappingsChange = (value) => {
    this.setState(prev =>
      ({
        formData: {
          ...prev.formData,
          variablesMapping: value,
        },
      }))
  }

  handleFormEdit = (formData) => {
    this.setState({ formData })
  }

  handleSubmit = () => {
    const variablesMapping = this.state.formData.variablesMapping
      .map(pair => `${pair[0]}-${pair[1]}`)
      .join(',')
    this.props.actions.submitData({
      ...this.state.formData,
      variablesMapping,
      attributesToCheck: this.state.attributes,
    })
  }

  render() {
    const { columns, localize } = this.props
    const {
      formData: { statUnitType, variablesMapping },
      attributes,
      file,
      fileError,
    } = this.state
    const options = this.getLocalizedOptions()
    const activeColumns = columns[getTypeKeyForColumns(statUnitType)]
    return (
      <Form
        schema={schema}
        value={this.state.formData}
        onChange={this.handleFormEdit}
        onSubmit={this.handleSubmit}
        className={styles.root}
      >
        <Dropzone
          ref={(dz) => { this.dropzone = dz }}
          onDrop={this.handleDropFile}
          multiple={false}
          className={styles['dz-container']}
        >
          <Message
            error={fileError !== undefined}
            success={fileError === undefined && file !== undefined}
          >
            <Icon name="upload" size="huge" />
            <Message.Content>
              <Message.Header content={localize('DropXmlOrCsvFileAmigo')} />
              {!fileError && file && <p><Icon name="check" />{file.name}</p>}
              {fileError && <p><Icon name="close" />{fileError}</p>}
            </Message.Content>
          </Message>
        </Dropzone>
        <div className={styles['fields-container']}>
          <Text
            name="name"
            label={localize('Name')}
            title={localize('Name')}
          />
          <Text
            name="description"
            label={localize('Description')}
            title={localize('Description')}
          />
          <Text
            name="restrictions"
            label={localize('Restrictions')}
            title={localize('Restrictions')}
          />
          <Form.Group width="equals">
            <Select
              name="statUnitType"
              options={options.statUnitType}
              label={localize('StatUnit')}
              title={localize('StatUnit')}
            />
            <Select
              name="allowedOperations"
              options={options.allowedOperations}
              label={localize('AllowedOperations')}
              title={localize('AllowedOperations')}
            />
            <Select
              name="priority"
              options={options.priorities}
              label={localize('Priority')}
              title={localize('Priority')}
            />
          </Form.Group>
          <Form.Errors />
        </div>
        <Accordion className={styles['mappings-container']}>
          <Accordion.Title>
            <Icon name="dropdown" />
            {localize('VariablesMapping')}
          </Accordion.Title>
          <Accordion.Content>
            <MappingsEditor
              name="variablesMapping"
              value={variablesMapping}
              onChange={this.handleMappingsChange}
              attributes={attributes}
              columns={activeColumns}
            />
          </Accordion.Content>
        </Accordion>
        <div style={{ width: '100%' }}>
          <Button
            as={Link} to="/datasources"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            floated="left"
            size="small"
            color="grey"
            type="button"
          />
          <Button
            type="submit"
            content={localize('Submit')}
            className={styles.submit}
            floated="right"
            primary
          />
        </div>
      </Form>
    )
  }
}

export default Create
