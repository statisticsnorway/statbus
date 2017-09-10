import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'
import { map, equals } from 'ramda'
import { Accordion, Icon, Message } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'

import MappingsEditor from 'components/DataSourceMapper'
import { camelize } from 'helpers/camelCase'
import * as enums from 'helpers/enums'
import { parseCSV, parseXML } from 'helpers/parseDataSourceAttributes'
import schema from './schema'
import styles from './styles.pcss'

const unmap = map(([value, text]) => ({ value, text }))
const statunitOptions = unmap([...enums.statUnitTypes]).filter(x => x.value < 4)
const priorities = unmap([...enums.dataSourcePriorities])
const operations = unmap([...enums.dataSourceOperations])

const getTypeKeyForColumns = key => camelize(enums.statUnitTypes.get(key))

const unitTypeArray = arrayOf(shape({
  name: string,
})).isRequired

class TemplateForm extends React.Component {

  static propTypes = {
    columns: shape({
      enterpriseGroup: unitTypeArray,
      enterpriseUnit: unitTypeArray,
      legalUnit: unitTypeArray,
      localUnit: unitTypeArray,
    }).isRequired,
    formData: shape({}),
    localize: func.isRequired,
    navigateBack: func.isRequired,
    submitData: func.isRequired,
  }

  static defaultProps = {
    formData: undefined,
  }

  state = {
    formData: this.props.formData || schema.default(),
    file: undefined,
    fileError: undefined,
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(this.props.formData, nextProps.formData)) {
      this.setState({ formData: nextProps.formData })
    }
  }

  componentWillUnmount() {
    this.revokeCurrentFileUrl()
  }

  getLocalizedOptions() {
    const localizeArray = map(x => ({ ...x, text: this.props.localize(x.text) }))
    const attributes = this.state.formData.attributesToCheck.map(x => ({ text: x, value: x }))
    return {
      statUnitType: localizeArray(statunitOptions),
      attributesToCheck: localizeArray(attributes),
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
        const attribs = file.name.endsWith('.xml')
          ? parseXML(e.target.result)
          : file.name.endsWith('.csv')
            ? parseCSV(e.target.result)
            : []
        if (attribs.length === 0) {
          this.setState(prev => ({
            fileError: this.props.localize('ParseAttributesNotFound'),
            formData: { ...prev.formData, variablesMapping: [] },
          }))
        } else {
          this.setState(prev => ({
            file,
            fileError: undefined,
            formData: {
              ...prev.formData,
              variablesMapping: [],
              attributesToCheck: attribs,
            },
          }))
        }
      }
      reader.readAsText(file)
    } catch (error) {
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
    const { formData } = this.state
    const variablesMapping = formData.variablesMapping
      .map(pair => `${pair[0]}-${pair[1]}`)
      .join(',')
    this.props.submitData({
      ...formData,
      variablesMapping,
    })
  }

  renderDropzone() {
    const { localize } = this.props
    const { file, fileError } = this.state
    return (
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
    )
  }

  renderMappingsEditor() {
    const { columns, localize } = this.props
    const { formData: { statUnitType, attributesToCheck, variablesMapping } } = this.state
    const activeColumns = columns[getTypeKeyForColumns(statUnitType)]
    return (
      <Accordion className={styles['mappings-container']}>
        <Accordion.Title>
          <Icon name="dropdown" />
          {localize('VariablesMapping')}
        </Accordion.Title>
        <br />
        <Accordion.Content>
          <MappingsEditor
            name="variablesMapping"
            value={variablesMapping}
            onChange={this.handleMappingsChange}
            attributes={attributesToCheck}
            columns={activeColumns}
          />
        </Accordion.Content>
      </Accordion>
    )
  }

  render() {
    const { localize, navigateBack } = this.props
    const options = this.getLocalizedOptions()
    return (
      <SchemaForm
        schema={schema}
        value={this.state.formData}
        onChange={this.handleFormEdit}
        onSubmit={this.handleSubmit}
        className={styles.root}
      >
        {this.renderDropzone()}
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
        </div>
        {this.renderMappingsEditor()}
        <div style={{ width: '100%' }}>
          <Button
            content={localize('Back')}
            onClick={navigateBack}
            icon={<Icon size="large" name="chevron left" />}
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
      </SchemaForm>
    )
  }
}

export default TemplateForm
