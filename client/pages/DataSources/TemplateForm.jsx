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
}

export default TemplateForm
